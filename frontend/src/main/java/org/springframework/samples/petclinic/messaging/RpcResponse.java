/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Envelope for every RPC reply received from the backend. The payload is kept as a raw
 * {@link JsonNode} so the caller can bind it to the concrete type it expects.
 */
public class RpcResponse {

	private boolean success;

	private String errorCode;

	private String errorMessage;

	private JsonNode payload;

	public boolean isSuccess() {
		return success;
	}

	public void setSuccess(boolean success) {
		this.success = success;
	}

	public String getErrorCode() {
		return errorCode;
	}

	public void setErrorCode(String errorCode) {
		this.errorCode = errorCode;
	}

	public String getErrorMessage() {
		return errorMessage;
	}

	public void setErrorMessage(String errorMessage) {
		this.errorMessage = errorMessage;
	}

	public JsonNode getPayload() {
		return payload;
	}

	public void setPayload(JsonNode payload) {
		this.payload = payload;
	}

}
