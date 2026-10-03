import { resolveTimetableGroupVisibility } from './timetable-group-deduplication';

const group = (
  id: string,
  shortName: string,
  longName: string,
  department: string | null,
  entryIds: string[],
) => ({ id, shortName, longName, department, entryIds });

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

  it('never merges groups that public metadata can distinguish', () => {
    const visibility = resolveTimetableGroupVisibility([
      group('fb1', 'Veranstaltungen', 'Veranstaltungen', 'FB1', []),
      group('bbg', 'Veranstaltungen', 'Veranstaltungen Bernburg', 'BBG', []),
    ]);

    expect([...visibility.values()]).toEqual([true, true]);
  });
});
