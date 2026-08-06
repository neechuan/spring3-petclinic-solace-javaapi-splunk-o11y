/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.vet;

import java.util.ArrayList;
import java.util.List;

import jakarta.xml.bind.annotation.XmlElement;
import jakarta.xml.bind.annotation.XmlRootElement;

/**
 * Simple domain object representing a list of veterinarians. Mostly here to be used for
 * the 'vets' {@link org.springframework.web.servlet.view.xml.MarshallingView}.
 */
@XmlRootElement
public class Vets {

	private List<Vet> vets;

	@XmlElement
	public List<Vet> getVetList() {
		if (vets == null) {
			vets = new ArrayList<>();
		}
		return vets;
	}

}
