/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging.dto;

import java.util.ArrayList;
import java.util.List;

/**
 * Wire representation of a page of results, mirroring the fields of Spring Data's
 * {@code Page} needed by the frontend to rebuild a {@code PageImpl}.
 *
 * @param <T> the element type
 */
public class PageResponse<T> {

	private List<T> content = new ArrayList<>();

	private long totalElements;

	private int totalPages;

	private int number;

	private int size;

	public List<T> getContent() {
		return content;
	}

	public void setContent(List<T> content) {
		this.content = content;
	}

	public long getTotalElements() {
		return totalElements;
	}

	public void setTotalElements(long totalElements) {
		this.totalElements = totalElements;
	}

	public int getTotalPages() {
		return totalPages;
	}

	public void setTotalPages(int totalPages) {
		this.totalPages = totalPages;
	}

	public int getNumber() {
		return number;
	}

	public void setNumber(int number) {
		this.number = number;
	}

	public int getSize() {
		return size;
	}

	public void setSize(int size) {
		this.size = size;
	}

}
