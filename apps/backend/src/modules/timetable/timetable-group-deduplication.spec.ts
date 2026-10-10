import { resolveTimetableGroupVisibility } from './timetable-group-deduplication';

const group = (
  id: string,
  shortName: string,
  longName: string,
  department: string | null,
  entryIds: string[],
  contextIds: string[] = ['semester-1'],
) => ({ id, shortName, longName, department, entryIds, contextIds });

describe('resolveTimetableGroupVisibility', () => {
  it('keeps the populated representative of an exact public duplicate', () => {
    const visibility = resolveTimetableGroupVisibility([
      group('empty-alias', 'MER2', '2.Sem.Ernährungstherapie Master', 'FB1', []),
      group('working-alias', 'MER2', '2.Sem.Ernährungstherapie Master', 'FB1', [
        'lesson-1',
        'lesson-2',
      ]),
    ]);

    expect(visibility).toEqual(
      new Map([
        ['empty-alias', false],
        ['working-alias', true],
      ]),
    );
  });

  it('keeps exact labels separate when both carry different timetables', () => {
    const visibility = resolveTimetableGroupVisibility([
      group('first', 'SAME', 'Same public label', 'FB1', ['lesson-1']),
      group('second', 'SAME', 'Same public label', 'FB1', ['lesson-2']),
    ]);

    expect(visibility).toEqual(
      new Map([
        ['first', true],
        ['second', true],
      ]),
    );
  });

  it('consolidates aliases with the same non-empty timetable deterministically', () => {
    const visibility = resolveTimetableGroupVisibility([
      group('b', 'SAME', 'Same public label', 'FB1', ['lesson-2', 'lesson-1']),
      group('a', 'SAME', 'Same public label', 'FB1', ['lesson-1', 'lesson-2']),
    ]);

    expect(visibility).toEqual(
      new Map([
        ['b', false],
        ['a', true],
      ]),
    );
  });

  it('never merges same-named groups of different semester catalogues', () => {
    // Right after a semester change the window spans both catalogues. The
    // next semester's group has no lessons yet; it is still its own group.
    const visibility = resolveTimetableGroupVisibility([
      group('summer', 'MER2', '2.Sem.Ernährungstherapie Master', 'FB1', ['lesson-1'], ['ss']),
      group('winter', 'MER2', '2.Sem.Ernährungstherapie Master', 'FB1', [], ['ws']),
    ]);

    expect(visibility).toEqual(
      new Map([
        ['summer', true],
        ['winter', true],
      ]),
    );
  });

  it('keeps a group visible while it represents at least one of its semesters', () => {
    const visibility = resolveTimetableGroupVisibility([
      group('a-summer-only', 'SAME', 'Same public label', 'FB1', [], ['ss']),
      group('b-both', 'SAME', 'Same public label', 'FB1', [], ['ss', 'ws']),
      group('c-winter-only', 'SAME', 'Same public label', 'FB1', [], ['ws']),
    ]);

    // Summer: a represents, b is its alias. Winter: b represents, c is its alias.
    expect(visibility).toEqual(
      new Map([
        ['a-summer-only', true],
        ['b-both', true],
        ['c-winter-only', false],
      ]),
    );
  });

  it('never merges groups that public metadata can distinguish', () => {
    const visibility = resolveTimetableGroupVisibility([
      group('fb1', 'Veranstaltungen', 'Veranstaltungen', 'FB1', []),
      group('bbg', 'Veranstaltungen', 'Veranstaltungen Bernburg', 'BBG', []),
    ]);

    expect([...visibility.values()]).toEqual([true, true]);
  });
});
