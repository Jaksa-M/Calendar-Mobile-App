"""Algorithm for finding the earliest free slot for all participants.

Works over a set of busy intervals (the union of in-app appointments and busy
times from every participant's external calendars). It finds the earliest gaps
of the requested length within working hours."""
from __future__ import annotations

from datetime import datetime, time, timedelta

Interval = tuple[datetime, datetime]


def _merge(intervals: list[Interval]) -> list[Interval]:
    """Merge overlapping/adjacent intervals into a minimal set."""
    if not intervals:
        return []
    ordered = sorted(intervals, key=lambda x: x[0])
    merged = [ordered[0]]
    for start, end in ordered[1:]:
        last_start, last_end = merged[-1]
        if start <= last_end:
            merged[-1] = (last_start, max(last_end, end))
        else:
            merged.append((start, end))
    return merged


def _align_up(dt: datetime, granularity: timedelta) -> datetime:
    """Round a time up to the nearest multiple of the granularity (within the hour)."""
    step = int(granularity.total_seconds())
    secs = dt.minute * 60 + dt.second
    rem = secs % step
    if rem == 0 and dt.microsecond == 0:
        return dt.replace(microsecond=0)
    return (dt.replace(second=0, microsecond=0)
            + timedelta(seconds=(step - rem)))


def _working_windows(
    window_start: datetime, window_end: datetime,
    work_start_hour: int, work_end_hour: int,
) -> list[Interval]:
    """Working intervals (e.g. 9-17) per day, within the given window."""
    out: list[Interval] = []
    day = window_start.date()
    tz = window_start.tzinfo
    while day <= window_end.date():
        ws = datetime.combine(day, time(work_start_hour), tzinfo=tz)
        we = datetime.combine(day, time(work_end_hour), tzinfo=tz)
        s, e = max(ws, window_start), min(we, window_end)
        if s < e:
            out.append((s, e))
        day += timedelta(days=1)
    return out


def _subtract(base: Interval, busy: list[Interval]) -> list[Interval]:
    """Subtract all busy parts from the `base` interval; return the free segments."""
    segments = [base]
    for bs, be in busy:
        nxt: list[Interval] = []
        for cs, ce in segments:
            if be <= cs or bs >= ce:
                nxt.append((cs, ce))          # no overlap
            else:
                if bs > cs:
                    nxt.append((cs, bs))       # free before the busy part
                if be < ce:
                    nxt.append((be, ce))       # free after the busy part
        segments = nxt
    return segments


def suggest_slots(
    busy: list[Interval],
    duration: timedelta,
    window_start: datetime,
    window_end: datetime,
    work_start_hour: int = 9,
    work_end_hour: int = 17,
    granularity: timedelta = timedelta(minutes=15),
    max_results: int = 3,
) -> list[Interval]:
    """Return up to `max_results` earliest free slots of length `duration`."""
    busy = _merge([b for b in busy if b[1] > window_start and b[0] < window_end])
    results: list[Interval] = []
    for ws, we in _working_windows(window_start, window_end,
                                   work_start_hour, work_end_hour):
        for fs, fe in _subtract((ws, we), busy):
            start = _align_up(fs, granularity)
            while start + duration <= fe:
                results.append((start, start + duration))
                if len(results) >= max_results:
                    return results
                start += granularity
    return results
