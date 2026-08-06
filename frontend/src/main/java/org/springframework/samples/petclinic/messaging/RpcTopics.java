/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging;

/**
 * Topic contract shared (by convention) with the backend replier. The frontend publishes
 * requests to {@code petclinic/rpc/<operation>}; the backend subscribes to
 * {@code petclinic/rpc/>}.
 */
public final class RpcTopics {

	public static final String PREFIX = "petclinic/rpc/";

	public static final String OWNER_FIND_BY_ID = "owner/findById";

	public static final String OWNER_FIND_BY_LAST_NAME = "owner/findByLastName";

	public static final String OWNER_SAVE = "owner/save";

	public static final String PETTYPE_FIND_ALL = "pettype/findAll";

	public static final String VET_FIND_ALL = "vet/findAll";

	public static final String VET_FIND_ALL_PAGED = "vet/findAllPaged";

	private RpcTopics() {
	}

}
