.pragma library

const MAX_TEXT = 64

function parsePayload(raw) {
  var text = String(raw || "").trim()
  if (!text)
    return { ok: false, stale: true, updated: "", htb: null, thm: null, cylab: null }
  try {
    var data = JSON.parse(text)
    return {
      ok: data.ok === true,
      stale: data.stale === true,
      updated: sanitizeText(data.updated || "", 40),
      htb: sanitizeHtb(data.htb),
      thm: sanitizeThm(data.thm),
      cylab: sanitizeCylab(data.cylab)
    }
  } catch (e) {
    return { ok: false, stale: true, updated: "", htb: null, thm: null, cylab: null }
  }
}

function sanitizeHtb(p) {
  if (!p)
    return null
  return {
    ok: p.ok === true,
    stale: p.stale === true,
    error: sanitizeText(p.error || "", 80),
    username: sanitizeText(p.username, MAX_TEXT),
    rank: sanitizeText(p.rank, 48),
    ranking: toInt(p.ranking),
    points: toInt(p.points),
    userOwns: toInt(p.userOwns),
    systemOwns: toInt(p.systemOwns)
  }
}

function sanitizeThm(p) {
  if (!p)
    return null
  return {
    ok: p.ok === true,
    stale: p.stale === true,
    error: sanitizeText(p.error || "", 80),
    username: sanitizeText(p.username, MAX_TEXT),
    level: toInt(p.level),
    rank: sanitizeText(p.rank, 48),
    topPercentage: toInt(p.topPercentage),
    points: toInt(p.points),
    badges: toInt(p.badges),
    rooms: toInt(p.rooms),
    streak: toInt(p.streak),
    maxStreak: toInt(p.maxStreak)
  }
}

function sanitizeCylab(p) {
  if (!p)
    return null
  return {
    ok: p.ok === true,
    stale: p.stale === true,
    error: sanitizeText(p.error || "", 80),
    username: sanitizeText(p.username, MAX_TEXT),
    solved: toInt(p.solved),
    available: toInt(p.available),
    easySolved: toInt(p.easySolved),
    easyTotal: toInt(p.easyTotal),
    mediumSolved: toInt(p.mediumSolved),
    mediumTotal: toInt(p.mediumTotal),
    hardSolved: toInt(p.hardSolved),
    hardTotal: toInt(p.hardTotal),
    playlists: toInt(p.playlists)
  }
}

function toInt(value) {
  var n = Number(value)
  if (!isFinite(n) || n < 0)
    return 0
  return Math.round(n)
}

function sanitizeText(value, max) {
  var t = String(value === undefined || value === null ? "" : value)
  t = t.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/g, "")
  t = t.replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
  return t.length > max ? t.slice(0, max) : t
}

function formatNumber(value) {
  var n = toInt(value)
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

function barIcon() {
  if (typeof String.fromCodePoint === "function")
    return String.fromCodePoint(0xF023F)
  return "\uDB7F\uDE3F"
}

function htbRows(p) {
  if (!p)
    return []
  return [
    { label: "Rank", value: p.rank || "—" },
    { label: "Global position", value: p.ranking > 0 ? "#" + formatNumber(p.ranking) : "—" },
    { label: "Points", value: formatNumber(p.points) },
    { label: "User owns", value: String(p.userOwns) },
    { label: "Root owns", value: String(p.systemOwns) }
  ]
}

function thmRows(p) {
  if (!p)
    return []
  return [
    { label: "Level", value: "0x" + p.level.toString(16).toUpperCase() + "  ·  " + String(p.level) },
    { label: "Rank", value: p.rank || "—" },
    { label: "Points", value: formatNumber(p.points) },
    { label: "Rooms completed", value: String(p.rooms) },
    { label: "Badges", value: String(p.badges) }
  ]
}

function cylabRows(p) {
  if (!p)
    return []
  return [
    { label: "Solved", value: p.solved + " / " + p.available },
    { label: "Easy", value: p.easySolved + " / " + p.easyTotal },
    { label: "Medium", value: p.mediumSolved + " / " + p.mediumTotal },
    { label: "Hard", value: p.hardSolved + " / " + p.hardTotal },
    { label: "Playlists completed", value: String(p.playlists) }
  ]
}
