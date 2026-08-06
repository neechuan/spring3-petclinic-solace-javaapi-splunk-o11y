/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.solace.messaging.MessagingService;
import com.solace.messaging.publisher.OutboundMessage;
import com.solace.messaging.publisher.OutboundMessageBuilder;
import com.solace.messaging.receiver.InboundMessage;
import com.solace.messaging.receiver.RequestReplyMessageReceiver;
import com.solace.messaging.receiver.RequestReplyMessageReceiver.Replier;
import com.solace.messaging.resources.TopicSubscription;
import com.solace.messaging.trace.propagation.SolacePubSubPlusJavaTextMapGetter;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.samples.petclinic.messaging.dto.RpcResponse;
import org.springframework.stereotype.Component;

/**
 * Solace replier. Subscribes to {@code petclinic/rpc/>}, dispatches each request to
 * {@link PetClinicRpcService}, and sends the JSON reply back to the requestor using the
 * PubSub+ Messaging API for Java request/reply pattern.
 */
@Component
public class SolaceRpcListener {

	private static final Logger log = LoggerFactory.getLogger(SolaceRpcListener.class);

	// Reads the W3C trace context from an InboundMessage; carrier is the Solace message itself.
	private static final SolacePubSubPlusJavaTextMapGetter TRACE_GETTER = new SolacePubSubPlusJavaTextMapGetter();

	private final MessagingService messagingService;

	private final PetClinicRpcService service;

	private final ObjectMapper json;

	private RequestReplyMessageReceiver receiver;

	private OutboundMessageBuilder messageBuilder;

	public SolaceRpcListener(MessagingService messagingService, PetClinicRpcService service, ObjectMapper json) {
		this.messagingService = messagingService;
		this.service = service;
		this.json = json;
	}

	@PostConstruct
	public void start() {
		this.messageBuilder = messagingService.messageBuilder();

		String subscription = RpcTopics.PREFIX + ">";
		this.receiver = messagingService.requestReply()
			.createRequestReplyMessageReceiverBuilder()
			.build(TopicSubscription.of(subscription));
		this.receiver.start();
		this.receiver.receiveAsync(this::handleRequest);
		log.info("PetClinic backend listening for RPC requests on '{}'", subscription);
	}

	private void handleRequest(InboundMessage request, Replier replier) {
		if (replier == null) {
			log.warn("Received request without reply destination on {}, ignoring", request.getDestinationName());
			return;
		}

		String operation = request.getDestinationName().substring(RpcTopics.PREFIX.length());

		// Continue the trace started by the frontend/broker: parent the processing span to the message context.
		Context extracted = GlobalOpenTelemetry.getPropagators()
			.getTextMapPropagator()
			.extract(Context.current(), request, TRACE_GETTER);
		Span consumer = GlobalOpenTelemetry.getTracer("petclinic-backend")
			.spanBuilder(RpcTopics.PREFIX + operation + " process")
			.setSpanKind(SpanKind.CONSUMER)
			.setParent(extracted)
			.startSpan();
		try (Scope scope = consumer.makeCurrent()) {
			String body = request.getPayloadAsString();
			RpcResponse response = service.dispatch(operation, body);

			OutboundMessage reply = messageBuilder.build(json.writeValueAsString(response));
			replier.reply(reply);
		}
		catch (Exception ex) {
			log.error("Failed to send RPC reply for operation {}", operation, ex);
		}
		finally {
			consumer.end();
		}
	}

	@PreDestroy
	public void stop() {
		if (receiver != null) {
			receiver.terminate(500);
		}
	}

}
