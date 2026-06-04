/*
  STAGE I: CIRCUIT BREAKER TEST (RESET)
  =====================================
  Run this to RESET the circuit breaker to CLOSED state.
  Normal Notification flow should resume.
*/

SELECT public.reset_circuit_breaker('fcm');

SELECT service_name, state, failure_count FROM public.circuit_breakers WHERE service_name = 'fcm';
