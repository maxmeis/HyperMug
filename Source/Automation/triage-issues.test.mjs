import test from 'node:test';
import assert from 'node:assert/strict';
import { classify, missingComment, productionVersions, reportedVersion, triage } from './triage-issues.mjs';

const body = `### HyperMug marketing version\n1.2.3\n\n### HyperMug build number\n456\n\n### Install source\nGitHub production release`;
const releases = [{ tag_name: 'v1.2.4', draft: false, prerelease: false }, { tag_name: 'v1.2.3', draft: false, prerelease: false }, { tag_name: 'v1.3.0-beta.1', draft: false, prerelease: true }];

test('parses exact form fields and checks only published production tags', () => {
  assert.deepEqual(reportedVersion(body), { marketing: '1.2.3', build: '456', complete: true });
  assert.deepEqual(productionVersions(releases), ['1.2.4', '1.2.3']);
  assert.equal(classify(body, releases), 'version:older');
  assert.equal(classify(body.replace('1.2.3', '1.2.4'), releases), 'version:current');
  assert.equal(classify(body.replace('GitHub production release', 'Built from source'), releases), 'version:local');
  assert.equal(classify(body.replace('1.2.3', '0.9.0'), releases), 'version:unverified');
  assert.equal(classify(body.replace('456', 'not known yet'), releases), 'needs-version');
  assert.equal(classify(body.replace('1.2.3', 'unknown'), releases), 'needs-version');
  assert.equal(classify(body, null), null);
  assert.match(missingComment(body.replace('456', '_No response_')), /build number/);
  assert.match(missingComment(body.replace('1.2.3', 'unknown')), /marketing version/);
});

test('outsider issue and forged body identity cause no API calls', async () => {
  const request = () => { throw new Error('must not call API'); };
  await triage({ event: { issue: { number: 1, user: { login: 'someone-else' }, labels: [{ name: 'bug' }], body: `${body}\n### Author\nmaxmeis` } }, repo: 'maxmeis/HyperMug', releasesRepo: 'maxmeis/HyperMug', request });
  await triage({ event: { issue: { number: 1, user: { login: 'maxmeis' }, labels: [{ name: 'feature' }], body: '### Problem or use case\nNeed a feature' } }, repo: 'maxmeis/HyperMug', releasesRepo: 'maxmeis/HyperMug', request });
});

test('owner issue updates one existing bot comment only when content changes', async () => {
  const calls = [];
  const event = { issue: { number: 2, user: { login: 'maxmeis' }, labels: [{ name: 'bug' }, { name: 'needs-version' }], body: '### HyperMug marketing version\n_No response_' } };
  const wanted = missingComment(event.issue.body);
  const request = async (method, path, data) => {
    calls.push([method, path, data]);
    if (path.includes('/releases?')) return releases;
    if (path.includes('/comments?')) return [{ id: 5, body: wanted, user: { login: 'github-actions[bot]' } }];
    return null;
  };
  const args = { event, repo: 'maxmeis/HyperMug', releasesRepo: 'maxmeis/HyperMug', request };
  await triage(args);
  await triage(args);
  assert.equal(calls.filter(([method]) => method !== 'GET').length, 0);
});

test('owner issue creates one comment, updates it, and removes it when repaired', async () => {
  const comments = [];
  const calls = [];
  const event = { issue: { number: 3, user: { login: 'maxmeis' }, labels: [{ name: 'bug' }, { name: 'needs-version' }], body: '### HyperMug marketing version\n_No response_' } };
  const request = async (method, path, data) => {
    calls.push([method, path, data]);
    if (path.includes('/releases?')) return releases;
    if (path.includes('/comments?')) return [...comments];
    if (method === 'POST' && path.endsWith('/comments')) comments.push({ id: 10, body: data.body, user: { login: 'github-actions[bot]' } });
    if (method === 'PATCH') comments[0].body = data.body;
    if (method === 'DELETE' && path.includes('/comments/')) comments.length = 0;
    return null;
  };
  const args = { event, repo: 'maxmeis/HyperMug', releasesRepo: 'maxmeis/HyperMug', request };
  await triage(args);
  await triage(args);
  assert.equal(calls.filter(([method, path]) => method === 'POST' && path.endsWith('/comments')).length, 1);
  event.issue.body = '### HyperMug marketing version\n1.2.3';
  await triage(args);
  assert.equal(calls.filter(([method]) => method === 'PATCH').length, 1);
  event.issue.body = body;
  await triage(args);
  assert.equal(comments.length, 0);
  assert.equal(calls.filter(([method, path]) => method === 'DELETE' && path.includes('/comments/')).length, 1);
});
