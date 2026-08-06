/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging;

import com.fasterxml.jackson.databind.JavaType;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.type.TypeFactory;
import com.solace.messaging.MessagingService;
import com.solace.messaging.PubSubPlusClientException;
import com.solace.messaging.publisher.OutboundMessage;
import com.solace.messaging.publisher.OutboundMessageBuilder;
import com.solace.messaging.publisher.RequestReplyMessagePublisher;
import com.solace.messaging.receiver.InboundMessage;
import com.solace.messaging.resources.Topic;
import com.solace.messaging.trace.propagation.SolacePubSubPlusJavaTextMapSetter;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Component;

/**
 * Synchronous request/reply client for the backend. Serializes the request payload to
 * JSON, blocks on the Solace reply, and maps backend error codes onto the exception types
 * the original controllers already expect (e.g. a duplicate pet name becomes a
 * {@link DataIntegrityViolationException} whose message contains
 * {@code unique_owner_pet_name}).
 */
@Component
public class SolaceRpcClient {

	private static final Logger log = LoggerFactory.getLogger(SolaceRpcClient.class);

	// Writes the W3C trace context into an OutboundMessage; carrier is the Solace message itself.
	private static final SolacePubSubPlusJavaTextMapSetter TRACE_SETTER = new SolacePubSubPlusJavaTextMapSetter();

	private final MessagingService messagingService;

	private final ObjectMapper json;

	@Value("${solace.request.timeout-ms:10000}")
	private int timeoutMs;

	private RequestReplyMessagePublisher publisher;

	private OutboundMessageBuilder messageBuilder;

	public SolaceRpcClient(MessagingService messagingService, ObjectMapper json) {
		this.messagingService = messagingService;
		this.json = json;
	}

	@PostConstruct
	void init() {
		this.messageBuilder = messagingService.messageBuilder();
		this.publisher = messagingService.requestReply().createRequestReplyMessagePublisherBuilder().build();
		this.publisher.start();
	}

	public TypeFactory getTypeFactory() {
		return json.getTypeFactory();
	}

	/**
	 * Invoke a backend operation and bind the reply payload to the given class.
	 */
	public <T> T call(String operation, Object payload, Class<T> type) {
		return convert(callRaw(operation, payload), getTypeFactory().constructType(type));
	}

	/**
	 * Invoke a backend operation and bind the reply payload to the given (possibly
	 * generic) type.
	 */
	public <T> T call(String operation, Object payload, JavaType type) {
		return convert(callRaw(operation, payload), type);
	}

	private <T> T convert(JsonNode node, JavaType type) {
		if (node == null || node.isNull()) {
			return null;
		}
		return json.convertValue(node, type);
	}

	/**
	 * Invoke a backend operation and return the raw reply payload node (or {@code null}).
	 */
	public JsonNode callRaw(String operation, Object payload) {
		Span producer = GlobalOpenTelemetry.getTracer("petclinic-frontend")
			.spanBuilder(RpcTopics.PREFIX + operation + " publish")
			.setSpanKind(SpanKind.PRODUCER)
			.startSpan();
		try (Scope scope = producer.makeCurrent()) {
			String body = (payload == null) ? "{}" : json.writeValueAsString(payload);

			OutboundMessage request = messageBuilder.build(body);
			// Inject the current trace context so the broker and backend continue the same trace.
			GlobalOpenTelemetry.getPropagators()
				.getTextMapPropagator()
				.inject(Context.current(), request, TRACE_SETTER);
			Topic topic = Topic.of(RpcTopics.PREFIX + operation);
			InboundMessage replyMessage = publisher.publishAwaitResponse(request, topic, timeoutMs);

			String replyText = replyMessage.getPayloadAsString();
			RpcResponse response = json.readValue(replyText, RpcResponse.class);
			if (!response.isSuccess()) {
				throw toException(response);
			}
			return response.getPayload();
		}
		catch (PubSubPlusClientException ex) {
			throw new IllegalStateException("Solace RPC call failed for operation '" + operation + "'", ex);
		}
		catch (InterruptedException ex) {
			Thread.currentThread().interrupt();
			throw new IllegalStateException("Solace RPC call interrupted for operation '" + operation + "'", ex);
		}
		catch (com.fasterxml.jackson.core.JacksonException ex) {
			throw new IllegalStateException("Failed to (de)serialize RPC message for operation '" + operation + "'",
					ex);
		}
		finally {
			producer.end();
		}
	}

	@PreDestroy
	void stop() {
		if (publisher != null) {
			publisher.terminate(500);
		}
	}

	private RuntimeException toException(RpcResponse response) {
		String code = response.getErrorCode();
		String message = response.getErrorMessage();
		if ("DUPLICATE_PET_NAME".equals(code)) {
			// Preserve the marker the controllers look for.
			return new DataIntegrityViolationException("unique_owner_pet_name violation: " + message);
		}
		return new IllegalStateException("Backend RPC error [" + code + "]: " + message);
	}

}
