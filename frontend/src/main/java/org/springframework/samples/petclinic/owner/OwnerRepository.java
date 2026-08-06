/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.owner;

import java.util.Optional;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

/**
 * Owner data access, as consumed by the controllers. In the frontend this is backed by a
 * Solace request/reply call to the backend rather than JPA, but the method contract is
 * unchanged so the controllers stay identical to the monolith.
 */
public interface OwnerRepository {

	Optional<Owner> findById(Integer id);

	Page<Owner> findByLastNameStartingWith(String lastName, Pageable pageable);

	Owner save(Owner owner);

	Owner saveAndFlush(Owner owner);

}
