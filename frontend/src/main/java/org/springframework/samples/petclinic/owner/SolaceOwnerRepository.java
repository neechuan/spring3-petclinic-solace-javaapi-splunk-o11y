/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.owner;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import com.fasterxml.jackson.databind.JavaType;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.samples.petclinic.messaging.PageResponse;
import org.springframework.samples.petclinic.messaging.RpcTopics;
import org.springframework.samples.petclinic.messaging.SolaceRpcClient;
import org.springframework.stereotype.Repository;

/**
 * Solace-backed {@link OwnerRepository}. Each method issues a request/reply call to the
 * backend and maps the reply back onto the domain model.
 */
@Repository
public class SolaceOwnerRepository implements OwnerRepository {

	private final SolaceRpcClient client;

	public SolaceOwnerRepository(SolaceRpcClient client) {
		this.client = client;
	}

	@Override
	public Optional<Owner> findById(Integer id) {
		Owner owner = client.call(RpcTopics.OWNER_FIND_BY_ID, Map.of("id", id), Owner.class);
		return Optional.ofNullable(owner);
	}

	@Override
	public Page<Owner> findByLastNameStartingWith(String lastName, Pageable pageable) {
		Map<String, Object> request = Map.of("lastName", lastName == null ? "" : lastName, "page",
				pageable.getPageNumber(), "size", pageable.getPageSize());
		JavaType type = client.getTypeFactory().constructParametricType(PageResponse.class, Owner.class);
		PageResponse<Owner> response = client.call(RpcTopics.OWNER_FIND_BY_LAST_NAME, request, type);
		return toPage(response, pageable);
	}

	@Override
	public Owner save(Owner owner) {
		Owner saved = client.call(RpcTopics.OWNER_SAVE, owner, Owner.class);
		if (saved != null) {
			owner.setId(saved.getId());
		}
		return saved;
	}

	@Override
	public Owner saveAndFlush(Owner owner) {
		return save(owner);
	}

	private Page<Owner> toPage(PageResponse<Owner> response, Pageable pageable) {
		if (response == null) {
			return new PageImpl<>(List.of(), pageable, 0);
		}
		return new PageImpl<>(response.getContent(), pageable, response.getTotalElements());
	}

}
