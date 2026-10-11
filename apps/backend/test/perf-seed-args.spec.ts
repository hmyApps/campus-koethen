import { profileNameFromArgs } from '../../../scripts/perf/dataset-profiles';

/**
 * `seed-perf-dataset.ts --reset` without `--profile` used to read
 * `args[indexOf('--profile') + 1]`, i.e. `args[0]`, and died with
 * `Unknown profile "--reset"` instead of using the documented default.
 */
describe('performance-seed profile argument', () => {
  it('defaults to realistic when --profile is absent', () => {
    expect(profileNameFromArgs([])).toBe('realistic');
    expect(profileNameFromArgs(['--reset'])).toBe('realistic');
  });

  it('reads the value after --profile wherever it stands', () => {
    expect(profileNameFromArgs(['--profile', 'stress'])).toBe('stress');
    expect(profileNameFromArgs(['--reset', '--profile', 'stress'])).toBe('stress');
  });

  it('falls back to realistic when --profile is the last argument', () => {
    expect(profileNameFromArgs(['--profile'])).toBe('realistic');
  });

  it('passes an unknown profile name through for the caller to reject', () => {
    expect(profileNameFromArgs(['--profile', 'huge'])).toBe('huge');
  });
});
