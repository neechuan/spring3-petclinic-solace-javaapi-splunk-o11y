/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.vet;

import java.util.Collection;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

/**
 * Vet data access, as consumed by the controllers. Backed by a Solace request/reply call
 * to the backend in the frontend.
 */
public interface VetRepository {

	Collection<Vet> findAll();

	Page<Vet> findAll(Pageable pageable);

}
