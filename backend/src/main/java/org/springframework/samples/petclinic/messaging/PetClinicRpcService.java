/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging;

import java.util.function.Function;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.samples.petclinic.messaging.dto.FindAllPagedRequest;
import org.springframework.samples.petclinic.messaging.dto.FindByIdRequest;
import org.springframework.samples.petclinic.messaging.dto.FindByLastNameRequest;
import org.springframework.samples.petclinic.messaging.dto.OwnerDto;
import org.springframework.samples.petclinic.messaging.dto.PageResponse;
import org.springframework.samples.petclinic.messaging.dto.RpcResponse;
import org.springframework.samples.petclinic.owner.Owner;
import org.springframework.samples.petclinic.owner.OwnerRepository;
import org.springframework.samples.petclinic.owner.PetTypeRepository;
import org.springframework.samples.petclinic.vet.Vet;
import org.springframework.samples.petclinic.vet.VetRepository;
import org.springframework.stereotype.Service;

/**
 * Executes the persistence operations requested over Solace and produces an
 * {@link RpcResponse}. This is the server-side counterpart of the frontend's
 * Solace-backed repositories.
 */
@Service
public class PetClinicRpcService {

	private static final Logger log = LoggerFactory.getLogger(PetClinicRpcService.class);

	private final OwnerRepository owners;

	private final PetTypeRepository petTypes;

	private final VetRepository vets;

	private final PetClinicMapper mapper;

	private final ObjectMapper json;

	public PetClinicRpcService(OwnerRepository owners, PetTypeRepository petTypes, VetRepository vets,
			PetClinicMapper mapper, ObjectMapper json) {
		this.owners = owners;
		this.petTypes = petTypes;
		this.vets = vets;
		this.mapper = mapper;
		this.json = json;
	}

	/**
	 * Dispatch a request to the matching persistence operation.
	 * @param operation the operation suffix (topic without the {@code petclinic/rpc/}
	 * prefix)
	 * @param body the JSON request payload
	 * @return the reply envelope, never {@code null}
	 */
	public RpcResponse dispatch(String operation, String body) {
		try {
			return switch (operation) {
				case RpcTopics.OWNER_FIND_BY_ID -> ownerFindById(body);
				case RpcTopics.OWNER_FIND_BY_LAST_NAME -> ownerFindByLastName(body);
				case RpcTopics.OWNER_SAVE -> ownerSave(body);
				case RpcTopics.PETTYPE_FIND_ALL -> petTypeFindAll();
				case RpcTopics.VET_FIND_ALL -> vetFindAll();
				case RpcTopics.VET_FIND_ALL_PAGED -> vetFindAllPaged(body);
				default -> RpcResponse.error("UNKNOWN_OPERATION", "Unknown operation: " + operation);
			};
		}
		catch (DataIntegrityViolationException ex) {
			if (isDuplicatePetNameViolation(ex)) {
				return RpcResponse.error("DUPLICATE_PET_NAME", "already exists");
			}
			log.error("Data integrity violation handling operation {}", operation, ex);
			return RpcResponse.error("DATA_INTEGRITY_VIOLATION", messageOf(ex));
		}
		catch (Exception ex) {
			log.error("Failed to handle operation {}", operation, ex);
			return RpcResponse.error("INTERNAL_ERROR", messageOf(ex));
		}
	}

	private RpcResponse ownerFindById(String body) throws Exception {
		FindByIdRequest request = json.readValue(body, FindByIdRequest.class);
		return RpcResponse.ok(owners.findById(request.getId()).map(mapper::toDto).orElse(null));
	}

	private RpcResponse ownerFindByLastName(String body) throws Exception {
		FindByLastNameRequest request = json.readValue(body, FindByLastNameRequest.class);
		Page<Owner> page = owners.findByLastNameStartingWith(request.getLastName(),
				PageRequest.of(request.getPage(), request.getSize()));
		return RpcResponse.ok(toPageResponse(page, mapper::toDto));
	}

	private RpcResponse ownerSave(String body) throws Exception {
		OwnerDto dto = json.readValue(body, OwnerDto.class);
		Owner saved = owners.saveAndFlush(mapper.toEntity(dto));
		return RpcResponse.ok(mapper.toDto(saved));
	}

	private RpcResponse petTypeFindAll() {
		return RpcResponse.ok(petTypes.findPetTypes().stream().map(mapper::toDto).toList());
	}

	private RpcResponse vetFindAll() {
		return RpcResponse.ok(vets.findAll().stream().map(mapper::toDto).toList());
	}

	private RpcResponse vetFindAllPaged(String body) throws Exception {
		FindAllPagedRequest request = json.readValue(body, FindAllPagedRequest.class);
		Page<Vet> page = vets.findAll(PageRequest.of(request.getPage(), request.getSize()));
		return RpcResponse.ok(toPageResponse(page, mapper::toDto));
	}

	private <E, D> PageResponse<D> toPageResponse(Page<E> page, Function<E, D> converter) {
		PageResponse<D> response = new PageResponse<>();
		response.setContent(page.getContent().stream().map(converter).toList());
		response.setTotalElements(page.getTotalElements());
		response.setTotalPages(page.getTotalPages());
		response.setNumber(page.getNumber());
		response.setSize(page.getSize());
		return response;
	}

	private boolean isDuplicatePetNameViolation(DataIntegrityViolationException ex) {
		String message = ex.getMessage();
		return message != null && message.toLowerCase().contains("unique_owner_pet_name");
	}

	private String messageOf(Exception ex) {
		return ex.getMessage() != null ? ex.getMessage() : ex.getClass().getSimpleName();
	}

}
