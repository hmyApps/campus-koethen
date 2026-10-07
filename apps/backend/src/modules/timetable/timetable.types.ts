import { ApiProperty } from '@nestjs/swagger';
import { ResponseMetaDto } from '../../common/dto/meta.dto';

/**
 * Public shapes for /v1/timetable*.
 *
 * There is deliberately NO external identifier anywhere in this file. Clients
 * see Campus UUIDs only; the WebUntis class id and school year id stop at the
 * adapter. A test asserts this, because leaking them would tie the app to a
 * third party's identifier space.
 */

export class TimetableGroupDto {
  @ApiProperty({ format: 'uuid', description: 'Stable Campus identifier.' })
  id!: string;

  @ApiProperty({ example: 'AIN2 - BT' }) shortName!: string;
  @ApiProperty({ example: 'AIN2-Angewandte Informatik Vertiefung: Biotechnologie' })
  longName!: string;

  @ApiProperty({ type: String, nullable: true, example: 'FB5' })
  department!: string | null;
}

export class TimetablePeriodDto {
  @ApiProperty({ format: 'uuid', description: 'Stable Campus identifier.' })
  id!: string;

  @ApiProperty({ description: 'Source-provided semester label. Never translated.' })
  name!: string;

  @ApiProperty({ format: 'date', example: '2026-10-05' }) validFrom!: string;
  @ApiProperty({ format: 'date', example: '2027-03-31' }) validTo!: string;

  @ApiProperty({ type: [TimetableGroupDto] }) groups!: TimetableGroupDto[];
}

export class TimetableModuleDto {
  @ApiProperty({ type: String, nullable: true, description: 'Source-provided module code.' })
  subjectCode!: string | null;

  @ApiProperty({ description: 'Source-provided module title. Never translated.' })
  title!: string;
}

export class TimetableTeacherDto {
  @ApiProperty({ description: 'Name as published by the source. Never translated.' })
  shortName!: string;

  @ApiProperty({ type: String, nullable: true })
  displayName!: string | null;
}

export class TimetableRoomDto {
  @ApiProperty() shortName!: string;
  @ApiProperty({ type: String, nullable: true }) longName!: string | null;
}

export class TimetableEntryDto {
  @ApiProperty({ format: 'uuid' }) id!: string;

  @ApiProperty({ format: 'date-time', description: 'Absolute instant, UTC.' })
  start!: string;

  @ApiProperty({ format: 'date-time' }) end!: string;

  @ApiProperty({
    example: 'Europe/Berlin',
    description: 'Business timezone the source schedules in.',
  })
  timezone!: string;

  @ApiProperty({ description: 'Subject name from the source. Never translated.' })
  title!: string;

  @ApiProperty({ type: String, nullable: true }) subjectCode!: string | null;

  @ApiProperty({
    enum: ['regular_teaching', 'additional', 'unknown'],
    description: 'Normalised. An unrecognised upstream value becomes `unknown`.',
  })
  type!: string;

  @ApiProperty({
    enum: ['regular', 'changed', 'cancelled', 'unknown'],
    description: 'Normalised. The client must render `unknown` neutrally rather than guess.',
  })
  status!: string;

  @ApiProperty({ type: [TimetableTeacherDto] }) teachers!: TimetableTeacherDto[];
  @ApiProperty({ type: [TimetableRoomDto] }) rooms!: TimetableRoomDto[];
  @ApiProperty({ type: [TimetableGroupDto] }) groups!: TimetableGroupDto[];

  @ApiProperty({ type: String, nullable: true }) note!: string | null;
  @ApiProperty({ type: String, nullable: true }) lessonInfo!: string | null;
}

export class TimetableDayDto {
  @ApiProperty({ example: '2026-07-20' }) date!: string;

  @ApiProperty({
    type: [TimetableEntryDto],
    description: 'Empty means a genuinely free day, not a loading failure.',
  })
  entries!: TimetableEntryDto[];
}

export class TimetableWeekDto {
  @ApiProperty({ type: TimetableGroupDto }) group!: TimetableGroupDto;

  @ApiProperty({ type: [TimetableDayDto], description: 'Every day of the requested range.' })
  days!: TimetableDayDto[];
}

export class TimetableLessonInfoDto {
  @ApiProperty({
    type: [String],
    description: 'Distinct lessonInfo texts exactly as stored for the selected group.',
  })
  values!: string[];

  @ApiProperty({
    description: 'Whether the covered timetable also contains entries without lessonInfo.',
  })
  hasWithoutInfo!: boolean;
}

export class TimetableStatusDto {
  @ApiProperty() featureEnabled!: boolean;
  @ApiProperty({ example: 270 }) groupCount!: number;

  @ApiProperty({ type: String, nullable: true, format: 'date-time' })
  lastGroupSyncAt!: string | null;

  @ApiProperty({ type: String, nullable: true, format: 'date-time' })
  lastEntrySyncAt!: string | null;

  @ApiProperty() dataStale!: boolean;

  @ApiProperty({ type: String, nullable: true, example: '2026-07-15' })
  coveredFrom!: string | null;

  @ApiProperty({ type: String, nullable: true, example: '2026-08-19' })
  coveredTo!: string | null;
}

// --- Response envelopes ------------------------------------------------------

export class TimetableGroupsResponseDto {
  @ApiProperty({ type: [TimetableGroupDto] }) data!: TimetableGroupDto[];
  @ApiProperty({ type: ResponseMetaDto }) meta!: ResponseMetaDto;
}

export class TimetableGroupResponseDto {
  @ApiProperty({ type: TimetableGroupDto }) data!: TimetableGroupDto;
  @ApiProperty({ type: ResponseMetaDto }) meta!: ResponseMetaDto;
}

export class TimetablePeriodsResponseDto {
  @ApiProperty({ type: [TimetablePeriodDto] }) data!: TimetablePeriodDto[];
  @ApiProperty({ type: ResponseMetaDto }) meta!: ResponseMetaDto;
}

export class TimetableModulesResponseDto {
  @ApiProperty({ type: [TimetableModuleDto] }) data!: TimetableModuleDto[];
  @ApiProperty({ type: ResponseMetaDto }) meta!: ResponseMetaDto;
}

export class TimetableWeekResponseDto {
  @ApiProperty({ type: TimetableWeekDto }) data!: TimetableWeekDto;
  @ApiProperty({ type: ResponseMetaDto }) meta!: ResponseMetaDto;
}

export class TimetableLessonInfoResponseDto {
  @ApiProperty({ type: TimetableLessonInfoDto }) data!: TimetableLessonInfoDto;
  @ApiProperty({ type: ResponseMetaDto }) meta!: ResponseMetaDto;
}

export class TimetableStatusResponseDto {
  @ApiProperty({ type: TimetableStatusDto }) data!: TimetableStatusDto;
  @ApiProperty({ type: ResponseMetaDto }) meta!: ResponseMetaDto;
}
