/*
 * The report format wai's bridge sends (apps/cli/src/telemetry.ts). Anything that doesn't match
 * exactly is dropped, so the collector never stores more than the documented fields.
 */

export interface Report {
  event: string
  detail: string
  version: string
  os: string
  arch: string
  client?: string
  install: string
  at: string
}

export const MAX_BODY = 64 * 1024
export const MAX_EVENTS = 50

const LIMITS: Record<keyof Report, number> = {
  arch: 16,
  at: 40,
  client: 32,
  detail: 300,
  event: 32,
  install: 64,
  os: 16,
  version: 32,
}

const isReport = (value: unknown): value is Report => {
  if (typeof value !== "object" || value === null) {
    return false
  }
  const fields = Object.entries(value)
  if (fields.some(([key]) => !(key in LIMITS))) {
    return false
  }
  for (const [key, limit] of Object.entries(LIMITS)) {
    const field = (value as Record<string, unknown>)[key]
    if (field === undefined && key === "client") {
      continue
    }
    if (typeof field !== "string" || field.length > limit) {
      return false
    }
  }
  return /^[a-z_]{1,32}$/u.test((value as Report).event)
}

// The valid reports in a request body; invalid entries are skipped, not fatal.
export const parseReports = (body: string): Report[] => {
  if (body.length > MAX_BODY) {
    return []
  }
  let parsed: unknown
  try {
    parsed = JSON.parse(body)
  } catch {
    return []
  }
  if (!Array.isArray(parsed)) {
    return []
  }
  return parsed.slice(0, MAX_EVENTS).filter((r) => isReport(r))
}
