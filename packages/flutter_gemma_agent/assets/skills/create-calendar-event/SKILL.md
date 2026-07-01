---
name: create-calendar-event
description: Create a calendar event.
---

# Create calendar event

## Instructions

Call the `run_intent` tool with the following exact parameters:

- intent: create_calendar_event
- parameters: A JSON string with the following fields:
  - title: the title of the event. String.
  - description: an optional description of the event. String.
  - day_offset: how many days from today the event is. Integer. 0 means today,
    1 means tomorrow, 2 means the day after tomorrow, and so on.
  - hour: the start hour in 24-hour time (0–23). Integer.
  - minute: the start minute (0–59). Integer. Defaults to 0.
  - duration_minutes: how long the event lasts, in minutes. Integer. Defaults to 60.

Do NOT compute calendar dates yourself — just pass `day_offset` (0 for today,
1 for tomorrow, …) with the `hour` and `minute`. The app converts them into the
exact date and time.

Example — "schedule lunch tomorrow at noon for 90 minutes":
`{ "title": "Lunch", "day_offset": 1, "hour": 12, "minute": 0, "duration_minutes": 90 }`
