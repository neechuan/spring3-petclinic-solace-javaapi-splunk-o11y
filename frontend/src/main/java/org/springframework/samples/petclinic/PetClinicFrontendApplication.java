/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * PetClinic client frontend. Serves the Thymeleaf UI and delegates all persistence to the
 * backend service over Solace (JCSMP request/reply).
 */
@SpringBootApplication
public class PetClinicFrontendApplication {

	public static void main(String[] args) {
		SpringApplication.run(PetClinicFrontendApplication.class, args);
	}

}
