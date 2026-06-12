const API_BASE = (import.meta as any).env?.VITE_API_BASE || 'http://localhost:8000/api/v1'

async function api(path: string, options?: RequestInit) {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: { message: res.statusText } }))
    throw new Error(
      err.error?.message ||
      err.detail?.error?.message ||
      err.detail?.message ||
      res.statusText,
    )
  }
  return res.json()
}

export async function fetchState() {
  const data = await api('/state')
  return data.data
}

export async function fetchCatastrophes() {
  const data = await api('/catastrophes')
  return data.data?.catastrophes || []
}

export async function triggerCatastrophe(zoneId: number, catastropheType: string) {
  const data = await api('/catastrophes', {
    method: 'POST',
    body: JSON.stringify({ zoneId, catastropheType }),
  })
  return data.data
}

export async function fetchView(viewName: string) {
  const data = await api(`/views/${viewName}`)
  return data.data?.rows || []
}

export async function tickSimulation() {
  const data = await api('/simulation/tick', { method: 'POST' })
  return data.data
}

export async function togglePause() {
  const data = await api('/simulation/pause', { method: 'POST' })
  return data.data
}

export async function setAuto(enabled: boolean) {
  const data = await api('/simulation/auto', {
    method: 'POST',
    body: JSON.stringify({ enabled }),
  })
  return data.data
}

export async function stormMode(count: number = 20) {
  const data = await api('/simulation/storm', {
    method: 'POST',
    body: JSON.stringify({ count, intensity: 'high' }),
  })
  return data.data
}

export async function closeIncident(incidentId: number) {
  const data = await api(`/incidents/${incidentId}/close`, { method: 'POST' })
  return data.data
}

export async function arriveAssignment(assignmentId: number) {
  const data = await api(`/assignments/${assignmentId}/arrive`, { method: 'POST' })
  return data.data
}

export async function failAssignment(assignmentId: number) {
  const data = await api(`/assignments/${assignmentId}/fail`, { method: 'POST' })
  return data.data
}

export async function finishAssignment(assignmentId: number) {
  const data = await api(`/assignments/${assignmentId}/finish`, { method: 'POST' })
  return data.data
}

export async function escalateOverdue() {
  const data = await api('/incidents/escalate-overdue', { method: 'POST' })
  return data.data
}

export async function reactivateResources() {
  const data = await api('/resources/reactivate-due', { method: 'POST' })
  return data.data
}
