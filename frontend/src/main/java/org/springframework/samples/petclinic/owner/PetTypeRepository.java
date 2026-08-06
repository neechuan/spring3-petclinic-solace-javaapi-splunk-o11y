/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.owner;

import java.util.List;

/**
 * Pet type data access, as consumed by the controllers. Backed by a Solace request/reply
 * call to the backend in the frontend.
 */
public interface PetTypeRepository {

	List<PetType> findPetTypes();

}
