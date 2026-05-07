package com.example.demo;

import org.springframework.context.annotation.Configuration;
import org.springframework.beans.factory.annotation.Value;

@Configuration
class AppConfig {
    @Value("${app.test.bean-count:1000000}")
    private int beanCount;

    @Value("${app.test.string-size:256}")
    private int stringSize;

    @Value("${app.test.array-size:10}")
    private int arraySize;
}