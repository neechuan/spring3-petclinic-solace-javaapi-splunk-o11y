/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.model;

import jakarta.validation.constraints.NotBlank;

/**
 * Simple JavaBean domain object adds a name property to <code>BaseEntity</code>. Used as
 * a base class for objects needing these properties.
 */
public class NamedEntity extends BaseEntity {

	@NotBlank
	private String name;

	public String getName() {
		return this.name;
	}

	public void setName(String name) {
		this.name = name;
	}

	@Override
	public String toString() {
		String name = this.getName();
		return name != null ? name : "<null>";
	}

}
