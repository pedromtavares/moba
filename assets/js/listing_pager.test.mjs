import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';

const source = await readFile(new URL('./listing_pager.js', import.meta.url), 'utf8');
const {fixedPageStarts, pageStarts} = await import(`data:text/javascript,${encodeURIComponent(source)}`);

test('fixed-size history shows five records per page and keeps the remainder', () => {
  assert.deepEqual(fixedPageStarts(0, 5), [0]);
  assert.deepEqual(fixedPageStarts(5, 5), [0]);
  assert.deepEqual(fixedPageStarts(13, 5), [0, 5, 10]);
});

test('a capped leaderboard uses up to five rows depending on available height', () => {
  const heights = Array(13).fill(64);
  assert.deepEqual(pageStarts(heights, 0, 600, 5), [0, 5, 10]);
  assert.deepEqual(pageStarts(heights, 0, 270, 5), [0, 4, 8, 12]);
});

test('fits whole rows with varying heights and accounts for the gap', () => {
  assert.deepEqual(pageStarts([72, 84, 76, 70, 65], 8, 165), [0, 2, 4]);
  assert.deepEqual(pageStarts([72, 84, 76, 70, 65], 8, 160), [0, 1, 2, 4]);
});

test('keeps every row reachable when a row is taller than the viewport', () => {
  assert.deepEqual(pageStarts([80, 140, 60, 25], 0, 100), [0, 1, 2]);
});

test('empty and fully visible listings have a single page', () => {
  assert.deepEqual(pageStarts([], 0, 0), [0]);
  assert.deepEqual(pageStarts([80, 80], 0, 160), [0]);
});
