/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging.dto;

/**
 * Generic envelope for every RPC reply. Carries either a payload (on success) or an error
 * code/message that the frontend maps back onto its own exception handling.
 */
public class RpcResponse {

	private boolean success;

	private String errorCode;

	private String errorMessage;

	private Object payload;

	public static RpcResponse ok(Object payload) {
		RpcResponse r = new RpcResponse();
		r.success = true;
		r.payload = payload;
		return r;
	}

	public static RpcResponse error(String code, String message) {
		RpcResponse r = new RpcResponse();
		r.success = false;
		r.errorCode = code;
		r.errorMessage = message;
		return r;
	}

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

	public Object getPayload() {
		return payload;
	}

	public void setPayload(Object payload) {
		this.payload = payload;
	}

}
