/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging.dto;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * Wire representation of a pet.
 */
public class PetDto {

	private Integer id;

	private String name;

	private LocalDate birthDate;

	private PetTypeDto type;

	private List<VisitDto> visits = new ArrayList<>();

	public Integer getId() {
		return id;
	}

	public void setId(Integer id) {
		this.id = id;
	}

	public String getName() {
		return name;
	}

	public void setName(String name) {
		this.name = name;
	}

	public LocalDate getBirthDate() {
		return birthDate;
	}

	public void setBirthDate(LocalDate birthDate) {
		this.birthDate = birthDate;
	}

	public PetTypeDto getType() {
		return type;
	}

	public void setType(PetTypeDto type) {
		this.type = type;
	}

	public List<VisitDto> getVisits() {
		return visits;
	}

	public void setVisits(List<VisitDto> visits) {
		this.visits = visits;
	}

}
