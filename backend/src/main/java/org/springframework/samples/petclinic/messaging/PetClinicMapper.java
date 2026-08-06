/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging;

import java.util.List;

import org.springframework.samples.petclinic.messaging.dto.OwnerDto;
import org.springframework.samples.petclinic.messaging.dto.PetDto;
import org.springframework.samples.petclinic.messaging.dto.PetTypeDto;
import org.springframework.samples.petclinic.messaging.dto.SpecialtyDto;
import org.springframework.samples.petclinic.messaging.dto.VetDto;
import org.springframework.samples.petclinic.messaging.dto.VisitDto;
import org.springframework.samples.petclinic.owner.Owner;
import org.springframework.samples.petclinic.owner.Pet;
import org.springframework.samples.petclinic.owner.PetType;
import org.springframework.samples.petclinic.owner.Visit;
import org.springframework.samples.petclinic.vet.Specialty;
import org.springframework.samples.petclinic.vet.Vet;
import org.springframework.stereotype.Component;

/**
 * Converts between JPA entities and their wire representations. Entity to DTO is used when
 * building replies; DTO to entity reconstructs the detached owner aggregate so that a
 * single {@code saveAndFlush} reproduces the monolith's persistence semantics.
 */
@Component
public class PetClinicMapper {

	public OwnerDto toDto(Owner owner) {
		if (owner == null) {
			return null;
		}
		OwnerDto dto = new OwnerDto();
		dto.setId(owner.getId());
		dto.setFirstName(owner.getFirstName());
		dto.setLastName(owner.getLastName());
		dto.setAddress(owner.getAddress());
		dto.setCity(owner.getCity());
		dto.setTelephone(owner.getTelephone());
		dto.setPets(owner.getPets().stream().map(this::toDto).toList());
		return dto;
	}

	public PetDto toDto(Pet pet) {
		PetDto dto = new PetDto();
		dto.setId(pet.getId());
		dto.setName(pet.getName());
		dto.setBirthDate(pet.getBirthDate());
		dto.setType(toDto(pet.getType()));
		dto.setVisits(pet.getVisits().stream().map(this::toDto).toList());
		return dto;
	}

	public VisitDto toDto(Visit visit) {
		VisitDto dto = new VisitDto();
		dto.setId(visit.getId());
		dto.setDate(visit.getDate());
		dto.setDescription(visit.getDescription());
		return dto;
	}

	public PetTypeDto toDto(PetType type) {
		if (type == null) {
			return null;
		}
		PetTypeDto dto = new PetTypeDto();
		dto.setId(type.getId());
		dto.setName(type.getName());
		return dto;
	}

	public VetDto toDto(Vet vet) {
		VetDto dto = new VetDto();
		dto.setId(vet.getId());
		dto.setFirstName(vet.getFirstName());
		dto.setLastName(vet.getLastName());
		dto.setSpecialties(vet.getSpecialties().stream().map(this::toDto).toList());
		return dto;
	}

	public SpecialtyDto toDto(Specialty specialty) {
		SpecialtyDto dto = new SpecialtyDto();
		dto.setId(specialty.getId());
		dto.setName(specialty.getName());
		return dto;
	}

	/**
	 * Rebuild a detached {@link Owner} aggregate from its wire representation. Existing pets
	 * and visits keep their identifiers (so they are merged/updated); new ones have a null
	 * id and are inserted.
	 */
	public Owner toEntity(OwnerDto dto) {
		Owner owner = new Owner();
		owner.setId(dto.getId());
		owner.setFirstName(dto.getFirstName());
		owner.setLastName(dto.getLastName());
		owner.setAddress(dto.getAddress());
		owner.setCity(dto.getCity());
		owner.setTelephone(dto.getTelephone());
		List<PetDto> pets = dto.getPets();
		if (pets != null) {
			for (PetDto petDto : pets) {
				// getPets() exposes the internal list, so we can attach pets that already
				// have an id (which addPet() would otherwise skip).
				owner.getPets().add(toEntity(petDto));
			}
		}
		return owner;
	}

	private Pet toEntity(PetDto dto) {
		Pet pet = new Pet();
		pet.setId(dto.getId());
		pet.setName(dto.getName());
		pet.setBirthDate(dto.getBirthDate());
		if (dto.getType() != null) {
			PetType type = new PetType();
			type.setId(dto.getType().getId());
			type.setName(dto.getType().getName());
			pet.setType(type);
		}
		List<VisitDto> visits = dto.getVisits();
		if (visits != null) {
			for (VisitDto visitDto : visits) {
				Visit visit = new Visit();
				visit.setId(visitDto.getId());
				visit.setDate(visitDto.getDate());
				visit.setDescription(visitDto.getDescription());
				pet.getVisits().add(visit);
			}
		}
		return pet;
	}

}
