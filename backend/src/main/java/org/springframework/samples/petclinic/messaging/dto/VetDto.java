/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging.dto;

import java.util.ArrayList;
import java.util.List;

/**
 * Wire representation of a veterinarian.
 */
public class VetDto {

	private Integer id;

	private String firstName;

	private String lastName;

	private List<SpecialtyDto> specialties = new ArrayList<>();

	public Integer getId() {
		return id;
	}

	public void setId(Integer id) {
		this.id = id;
	}

	public String getFirstName() {
		return firstName;
	}

	public void setFirstName(String firstName) {
		this.firstName = firstName;
	}

	public String getLastName() {
		return lastName;
	}

	public void setLastName(String lastName) {
		this.lastName = lastName;
	}

	public List<SpecialtyDto> getSpecialties() {
		return specialties;
	}

	public void setSpecialties(List<SpecialtyDto> specialties) {
		this.specialties = specialties;
	}

}
