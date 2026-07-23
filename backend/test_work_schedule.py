import unittest
from datetime import datetime
from zoneinfo import ZoneInfo

from work_schedule_rules import (
    DEFAULT_INTERN_WORK_SCHEDULE,
    is_start_within_schedule,
    time_on_day,
    validate_work_schedule,
)


class WorkScheduleRulesTest(unittest.TestCase):
    def setUp(self):
        self.schedule = validate_work_schedule(DEFAULT_INTERN_WORK_SCHEDULE)
        self.timezone = ZoneInfo("America/Sao_Paulo")

    def at(self, hour: int, minute: int) -> datetime:
        return datetime(2026, 7, 17, hour, minute, tzinfo=self.timezone)

    def test_start_window_boundaries_are_inclusive(self):
        self.assertTrue(is_start_within_schedule(self.at(13, 25), self.schedule))
        self.assertTrue(is_start_within_schedule(self.at(19, 25), self.schedule))

    def test_start_outside_window_is_blocked(self):
        self.assertFalse(is_start_within_schedule(self.at(13, 24), self.schedule))
        self.assertFalse(is_start_within_schedule(self.at(19, 26), self.schedule))

    def test_weekend_start_always_requires_approval(self):
        saturday = datetime(2026, 7, 18, 13, 30, tzinfo=self.timezone)
        sunday = datetime(2026, 7, 19, 13, 30, tzinfo=self.timezone)
        self.assertFalse(is_start_within_schedule(saturday, self.schedule))
        self.assertFalse(is_start_within_schedule(sunday, self.schedule))

    def test_default_overtime_threshold_is_1935(self):
        threshold = time_on_day(
            self.at(18, 0).date(),
            self.schedule["overtime_prompt_after"],
            self.schedule["timezone"],
        )
        self.assertEqual(threshold, self.at(19, 35))

    def test_invalid_schedule_is_rejected(self):
        with self.assertRaises(Exception):
            validate_work_schedule({"shift_start": "25:00"})


if __name__ == "__main__":
    unittest.main()
