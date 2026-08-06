/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.model;

import java.io.Serializable;

/**
 * Simple JavaBean domain object with an id property. Used as a base class for objects
 * needing this property. This is the frontend (non-persistent) counterpart of the backend
 * entity.
 */
public class BaseEntity implements Serializable {

	private Integer id;

	public Integer getId() {
		return id;
	}

	public void setId(Integer id) {
		this.id = id;
	}

	public boolean isNew() {
		return this.id == null;
	}

}
