/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.vet;

import java.util.Collection;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.databind.JavaType;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.samples.petclinic.messaging.PageResponse;
import org.springframework.samples.petclinic.messaging.RpcTopics;
import org.springframework.samples.petclinic.messaging.SolaceRpcClient;
import org.springframework.stereotype.Repository;

/**
 * Solace-backed {@link VetRepository}.
 */
@Repository
public class SolaceVetRepository implements VetRepository {

	private final SolaceRpcClient client;

	public SolaceVetRepository(SolaceRpcClient client) {
		this.client = client;
	}

	@Override
	public Collection<Vet> findAll() {
		JavaType type = client.getTypeFactory().constructCollectionType(List.class, Vet.class);
		List<Vet> vets = client.call(RpcTopics.VET_FIND_ALL, null, type);
		return vets != null ? vets : List.of();
	}

	@Override
	public Page<Vet> findAll(Pageable pageable) {
		Map<String, Object> request = Map.of("page", pageable.getPageNumber(), "size", pageable.getPageSize());
		JavaType type = client.getTypeFactory().constructParametricType(PageResponse.class, Vet.class);
		PageResponse<Vet> response = client.call(RpcTopics.VET_FIND_ALL_PAGED, request, type);
		if (response == null) {
			return new PageImpl<>(List.of(), pageable, 0);
		}
		return new PageImpl<>(response.getContent(), pageable, response.getTotalElements());
	}

}
