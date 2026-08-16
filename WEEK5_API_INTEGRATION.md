# Week 5 API Integration

## API Name

Open-Meteo Weather Forecast API

Reference: `https://open-meteo.com/en/docs`

## API Purpose

FloodGuard uses Open-Meteo to retrieve live weather and rainfall forecast data for Baliwag, Bulacan. The data helps users monitor rainfall conditions that may affect flood risk.

## Endpoint Used

`https://api.open-meteo.com/v1/forecast`

## Request Method Implemented

- `GET`: retrieves current temperature, current precipitation, rain, weather code, and 3-day daily forecast data.

Open-Meteo's forecast endpoint is a read-only public weather API, so a `POST` request is not applicable for this integration.

## Query Parameters

- `latitude`
- `longitude`
- `current=temperature_2m,precipitation,rain,weather_code`
- `daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum`
- `timezone=auto`
- `forecast_days=3`

## Features Added

- Live forecast data displayed in the Forecast screen.
- HTTP GET request using the `http` package.
- JSON response parsing into typed Dart models.
- Loading state while the request is running.
- Error state for failed or invalid API responses.
- Refresh button and pull-to-refresh support.
- API request details and JSON response sample displayed in the app for screenshots.

## Files Changed

- `lib/services/weather_service.dart`
- `lib/screens/forecast_screen.dart`
