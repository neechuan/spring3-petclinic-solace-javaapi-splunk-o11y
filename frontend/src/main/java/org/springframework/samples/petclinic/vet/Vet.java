/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.vet;

import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

import org.springframework.samples.petclinic.model.NamedEntity;
import org.springframework.samples.petclinic.model.Person;

import jakarta.xml.bind.annotation.XmlElement;

/**
 * Simple JavaBean domain object representing a veterinarian. Frontend (non-persistent)
 * counterpart of the backend entity. A real {@code setSpecialties} is provided so Jackson
 * can populate the specialties from the backend reply.
 */
public class Vet extends Person {

	private Set<Specialty> specialties;

	protected Set<Specialty> getSpecialtiesInternal() {
		if (this.specialties == null) {
			this.specialties = new HashSet<>();
		}
		return this.specialties;
	}

	@XmlElement
	public List<Specialty> getSpecialties() {
		return getSpecialtiesInternal().stream()
			.sorted(Comparator.comparing(NamedEntity::getName))
			.collect(Collectors.toList());
	}

	public void setSpecialties(List<Specialty> specialties) {
		getSpecialtiesInternal().clear();
		if (specialties != null) {
			getSpecialtiesInternal().addAll(specialties);
		}
	}

	public int getNrOfSpecialties() {
		return getSpecialtiesInternal().size();
	}

	public void addSpecialty(Specialty specialty) {
		getSpecialtiesInternal().add(specialty);
	}

}
