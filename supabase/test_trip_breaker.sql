/*
  STAGE I: CIRCUIT BREAKER TEST (TRIP)
  ====================================
  Run this to FORCE the circuit breaker OPEN.
  Any subsequent notifications should be skipped/fallback immediately.
*/

SELECT public.trip_circuit_breaker('fcm', true);

SELECT service_name, state, failure_count FROM public.circuit_breakers WHERE service_name = 'fcm';
