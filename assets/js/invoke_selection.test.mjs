import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source = await readFile(new URL('./invoke_selection.js', import.meta.url), 'utf8');
const {initialSelection, selectBuild, nameError} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const data = {
  avatars: [{id: 'jug', name: 'Juggernaut', role: 'carry'}, {id: 'axe', name: 'Axe', role: 'bruiser'}],
  skills: ['a', 'b', 'c', 'd'].map(id => ({id})),
  builds: {carry: [{skills: ['a', 'b', 'c']}, {skills: ['b', 'c', 'd']}], bruiser: [{skills: ['a', 'b', 'd']}, {skills: ['a', 'c', 'd']}]},
  initial: {avatar: 'jug', skills: ['a', 'b', 'c'], preset: 0, custom: false, name: 'Juggernaut', filter: null}, named: false
};

test('hero and preset selection are local and use the selected role builds', () => {
  let state = initialSelection(data);
  state = selectBuild(state, {type: 'avatar', id: 'axe'}, data);
  assert.deepEqual(state.skills, ['a', 'b', 'd']);
  assert.equal(state.name, 'Axe');
  state = selectBuild(state, {type: 'build', index: 1}, data);
  assert.deepEqual(state.skills, ['a', 'c', 'd']);
  assert.deepEqual(selectBuild(state, {type: 'avatar', id: 'locked'}, data), state);
});

test('custom skills cap at three and survive leaving and reopening planning', () => {
  let state = selectBuild(initialSelection(data), {type: 'mode'}, data);
  assert.deepEqual(state.skills, []);
  for (const id of ['a', 'b', 'c', 'd']) state = selectBuild(state, {type: 'skill', id}, data);
  assert.deepEqual(state.skills, ['a', 'b', 'c']);
  state = selectBuild(state, {type: 'mode'}, data);
  state = selectBuild(state, {type: 'mode'}, data);
  assert.deepEqual(state.skills, ['a', 'b', 'c']);
  state = selectBuild(state, {type: 'skill', id: 'b'}, data);
  state = selectBuild(state, {type: 'skill', id: 'd'}, data);
  assert.deepEqual(state.skills, ['a', 'c', 'd']);
  assert.deepEqual(selectBuild(state, {type: 'skill', id: 'locked'}, data), state);
});

test('filters toggle without changing the chosen hero or build', () => {
  const state = initialSelection(data);
  const filtered = selectBuild(state, {type: 'filter', role: 'bruiser'}, data);
  assert.equal(filtered.filter, 'bruiser');
  assert.equal(filtered.avatar, 'jug');
  assert.equal(selectBuild(filtered, {type: 'filter', role: 'bruiser'}, data).filter, null);
});

test('stale browser selections fall back safely, and invalid preset indexes are ignored', () => {
  assert.deepEqual(initialSelection(data, {...data.initial, avatar: 'deleted'}), initialSelection(data));
  assert.deepEqual(initialSelection(data, {...data.initial, skills: ['deleted']}), initialSelection(data));
  assert.equal(initialSelection(data, {...data.initial, preset: 100}).preset, null);
});

test('name validation is local while account names survive changing heroes', () => {
  assert.equal(nameError('x', true), 'Use 3–15 characters for your hero name.');
  assert.equal(nameError('Aether', true), '');
  assert.equal(nameError('', false), '');
  const state = selectBuild(initialSelection(data), {type: 'name', name: 'Aether'}, data);
  assert.equal(selectBuild(state, {type: 'avatar', id: 'axe'}, {...data, named: true}).name, 'Aether');
});
