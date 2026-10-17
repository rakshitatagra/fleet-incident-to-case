// Run once: sf apex run --file scripts/schedule-escalation.apex
// Calling it again is harmless; it will not create a second job.
CaseEscalationJob.scheduleHourly();
