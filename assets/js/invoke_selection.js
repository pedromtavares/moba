export function initialSelection(data, saved = data.initial) {
  const allowed = new Set(data.skills.map(skill => skill.id));
  const valid = data.avatars.some(avatar => avatar.id === saved?.avatar) && Array.isArray(saved.skills) && saved.skills.every(id => allowed.has(id));
  const choice = valid ? saved : data.initial;
  const avatar = data.avatars.find(avatar => avatar.id === choice.avatar) || data.avatars[0];
  const preset = Number.isInteger(choice.preset) && data.builds[avatar.role][choice.preset] ? choice.preset : null;
  return {
    avatar: avatar.id, skills: [...new Set(preset !== null && choice.custom !== true ? data.builds[avatar.role][preset].skills : choice.skills)].filter(id => allowed.has(id)).slice(0, 3),
    preset, custom: choice.custom === true,
    name: typeof choice.name === 'string' ? choice.name : data.initial.name,
    filter: ['tank', 'bruiser', 'carry', 'nuker', 'support'].includes(choice.filter) ? choice.filter : null
  };
}

export function selectBuild(state, action, data) {
  if (action.type === 'mode') return {...state, custom: !state.custom, ...(state.custom || state.preset === null ? {} : {skills: [], preset: null})};
  if (action.type === 'filter') return {...state, filter: state.filter === action.role || !action.role ? null : action.role};
  if (action.type === 'name') return {...state, name: action.name};
  if (action.type === 'avatar') {
    const avatar = data.avatars.find(avatar => avatar.id === action.id);
    if (!avatar) return state;
    const preset = state.custom ? null : state.preset ?? 0;
    return {...state, avatar: avatar.id, preset,
      skills: state.custom ? state.skills : [...data.builds[avatar.role][preset].skills],
      name: data.named ? state.name : avatar.name};
  }
  if (action.type === 'build') {
    const avatar = data.avatars.find(avatar => avatar.id === state.avatar);
    const build = data.builds[avatar.role][action.index];
    return build ? {...state, skills: [...build.skills], preset: action.index} : state;
  }
  if (action.type === 'skill' && state.custom && data.skills.some(skill => skill.id === action.id)) {
    const skills = state.skills.includes(action.id) ? state.skills.filter(id => id !== action.id) : state.skills.length < 3 ? [...state.skills, action.id] : state.skills;
    return {...state, skills, preset: null};
  }
  return state;
}

export function nameError(name, named) {
  return named && (typeof name !== 'string' || name.trim().length < 3 || name.trim().length > 15) ? 'Use 3–15 characters for your hero name.' : '';
}

export function nextDraftAvatar(avatars, drafted) {
  const available = avatars.filter(avatar => !drafted.has(avatar.id));
  return ['juggernaut', 'lina', 'tusk'].map(code => available.find(avatar => avatar.code === code)).find(Boolean) || available[0];
}

export function restoreDraftPicks(data, picks) {
  const roster = [];
  const skills = new Set(data.skills.map(skill => skill.id));
  for (const pick of Array.isArray(picks) ? picks : []) {
    const avatar = data.avatars.find(avatar => avatar.id === pick?.avatar);
    if (!avatar || roster.some(entry => entry.avatar === pick.avatar) || !Array.isArray(pick.skills) ||
        new Set(pick.skills).size !== 3 || pick.skills.length !== 3 || !pick.skills.every(id => skills.has(id))) continue;
    const build = Number.isInteger(pick.preset) ? data.builds[avatar.role][pick.preset] : null;
    const preset = build?.skills.every(id => pick.skills.includes(id)) ? pick.preset : null;
    roster.push({avatar: pick.avatar, skills: pick.skills, preset});
    if (roster.length === 3) break;
  }
  return roster;
}
