/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.owner;

import java.time.LocalDate;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.samples.petclinic.model.BaseEntity;

import jakarta.validation.constraints.NotBlank;

/**
 * Simple JavaBean domain object representing a visit. Frontend (non-persistent)
 * counterpart of the backend entity.
 */
public class Visit extends BaseEntity {

	@DateTimeFormat(pattern = "yyyy-MM-dd")
	private LocalDate date;

	@NotBlank
	private String description;

	/**
	 * Creates a new instance of Visit for tomorrow
	 */
	public Visit() {
		this.date = LocalDate.now().plusDays(1);
	}

	public LocalDate getDate() {
		return this.date;
	}

	public void setDate(LocalDate date) {
		this.date = date;
	}

	public String getDescription() {
		return this.description;
	}

	public void setDescription(String description) {
		this.description = description;
	}

}
