/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging;

import java.util.Properties;

import com.solace.messaging.MessagingService;
import com.solace.messaging.config.SolaceProperties.AuthenticationProperties;
import com.solace.messaging.config.SolaceProperties.ServiceProperties;
import com.solace.messaging.config.SolaceProperties.TransportLayerProperties;
import com.solace.messaging.config.profile.ConfigurationProfile;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Creates and connects the Solace {@link MessagingService} used by the frontend to issue
 * request/reply calls to the backend.
 */
@Configuration
public class SolaceConfig {

	private static final Logger log = LoggerFactory.getLogger(SolaceConfig.class);

	@Value("${solace.host:tcp://localhost:55554}")
	private String host;

	@Value("${solace.vpn:default}")
	private String vpn;

	@Value("${solace.username:default}")
	private String username;

	@Value("${solace.password:default}")
	private String password;

	@Bean(destroyMethod = "disconnect")
	public MessagingService messagingService() {
		Properties properties = new Properties();
		properties.setProperty(TransportLayerProperties.HOST, host);
		properties.setProperty(ServiceProperties.VPN_NAME, vpn);
		properties.setProperty(AuthenticationProperties.SCHEME_BASIC_USER_NAME, username);
		properties.setProperty(AuthenticationProperties.SCHEME_BASIC_PASSWORD, password);
		// Tolerate a broker that is still booting: keep retrying the initial connect
		// (~20 x 3s) instead of failing startup, then reconnect indefinitely if it drops.
		properties.setProperty(TransportLayerProperties.CONNECTION_RETRIES, "20");
		properties.setProperty(TransportLayerProperties.CONNECTION_RETRIES_PER_HOST, "2");
		properties.setProperty(TransportLayerProperties.RECONNECTION_ATTEMPTS, "-1");
		properties.setProperty(TransportLayerProperties.RECONNECTION_ATTEMPTS_WAIT_INTERVAL, "3000");

		MessagingService service = MessagingService.builder(ConfigurationProfile.V1).fromProperties(properties).build();
		service.connect();
		log.info("Connected to Solace broker at {} (vpn={})", host, vpn);
		return service;
	}

}
