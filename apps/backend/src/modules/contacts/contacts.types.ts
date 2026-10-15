import { ApiProperty } from '@nestjs/swagger';
import { ResponseMetaDto } from '../../common/dto/meta.dto';
import { ContentBlock } from '../../common/content/content-blocks';
import { RoomReferenceDto } from '../rooms/rooms.types';

/**
 * Public shapes for /v1/contact-areas*.
 *
 * Classes rather than interfaces so the published OpenAPI document carries
 * real response schemas.
 */

export class ContactPersonDto {
  @ApiProperty() name!: string;
  @ApiProperty({ type: String, nullable: true }) role!: string | null;
  @ApiProperty({ type: String, nullable: true }) description!: string | null;
  @ApiProperty({ type: String, nullable: true }) email!: string | null;
  @ApiProperty({ type: String, nullable: true }) phone!: string | null;
  @ApiProperty({ type: String, nullable: true }) website!: string | null;
  @ApiProperty({ type: String, nullable: true }) profileImage!: string | null;
  @ApiProperty() sortOrder!: number;

  @ApiProperty({
    type: [RoomReferenceDto],
    description: 'Rooms of the demo campus map. An empty list is normal — a contact needs no room.',
  })
  rooms!: RoomReferenceDto[];
}

export class ContactAreaListItemDto {
  @ApiProperty({ example: 'studierendenrat' }) slug!: string;
  @ApiProperty() name!: string;
  @ApiProperty() shortDescription!: string;
  @ApiProperty({ example: 'students-council' }) iconKey!: string;

  @ApiProperty({
    enum: ['koethen', 'bernburg', 'dessau'],
    example: 'koethen',
    description: 'Campus site the area belongs to. An area without a stored site is a Köthen one.',
  })
  site!: 'koethen' | 'bernburg' | 'dessau';

  @ApiProperty({
    type: String,
    nullable: true,
    example: '/v1/media/uploads/team_5a141d.jpg',
    description:
      'Image of the area, served by THIS API — the client never fetches from the CMS. Null when ' +
      'no image is set; the icon carries the area on its own in that case.',
  })
  image!: string | null;

  @ApiProperty() sortOrder!: number;

  @ApiProperty({ type: String, nullable: true }) generalEmail!: string | null;
  @ApiProperty({ type: String, nullable: true }) phone!: string | null;
  @ApiProperty({ type: String, nullable: true }) website!: string | null;
  @ApiProperty({ type: String, nullable: true }) appointmentBookingUrl!: string | null;
  @ApiProperty({ type: String, nullable: true }) address!: string | null;
  @ApiProperty({ type: String, nullable: true }) openingHours!: string | null;

  @ApiProperty({
    description: 'Zero is a valid, fully supported state — an area needs no contact person.',
  })
  personCount!: number;
}

export class ContactAreaDetailDto {
  @ApiProperty() slug!: string;
  @ApiProperty() name!: string;
  @ApiProperty() shortDescription!: string;
  @ApiProperty() iconKey!: string;

  @ApiProperty({
    enum: ['koethen', 'bernburg', 'dessau'],
    example: 'koethen',
    description: 'Campus site the area belongs to. An area without a stored site is a Köthen one.',
  })
  site!: 'koethen' | 'bernburg' | 'dessau';

  @ApiProperty({ type: String, nullable: true, example: '/v1/media/uploads/team_5a141d.jpg' })
  image!: string | null;

  @ApiProperty() sortOrder!: number;

  @ApiProperty({ type: String, nullable: true }) generalEmail!: string | null;
  @ApiProperty({ type: String, nullable: true }) phone!: string | null;
  @ApiProperty({ type: String, nullable: true }) website!: string | null;
  @ApiProperty({ type: String, nullable: true }) appointmentBookingUrl!: string | null;
  @ApiProperty({ type: String, nullable: true }) address!: string | null;
  @ApiProperty({ type: String, nullable: true }) openingHours!: string | null;
  @ApiProperty({
    type: 'array',
    items: { type: 'object', additionalProperties: true },
    description: 'Sanitised content blocks, same rules as news content.',
  })
  description!: ContentBlock[];

  @ApiProperty({ type: [ContactPersonDto], description: 'Active persons only; may be empty.' })
  persons!: ContactPersonDto[];

  @ApiProperty({
    type: [RoomReferenceDto],
    description: 'Rooms of the demo campus map. An empty list is normal — an area needs no room.',
  })
  rooms!: RoomReferenceDto[];
}

/**
 * One person inside the search index.
 *
 * Exactly the visible fields a reader could search for — no Strapi id, no
 * profile image, no sort order. A search index is a place where "everything we
 * happen to have" is the wrong default.
 */
export class ContactSearchPersonDto {
  @ApiProperty() name!: string;
  @ApiProperty({ type: String, nullable: true }) role!: string | null;
  @ApiProperty({ type: String, nullable: true }) description!: string | null;
  @ApiProperty({ type: String, nullable: true }) email!: string | null;
  @ApiProperty({ type: String, nullable: true }) phone!: string | null;
  @ApiProperty({ type: String, nullable: true }) website!: string | null;

  @ApiProperty({ type: [RoomReferenceDto] })
  rooms!: RoomReferenceDto[];
}

/** One area inside the search index, with its active persons. */
export class ContactSearchAreaDto {
  @ApiProperty({ example: 'studierendenrat' }) slug!: string;
  @ApiProperty() name!: string;
  @ApiProperty() shortDescription!: string;
  @ApiProperty({ example: 'students-council' }) iconKey!: string;

  @ApiProperty({
    enum: ['koethen', 'bernburg', 'dessau'],
    example: 'koethen',
    description: 'Campus site the area belongs to. An area without a stored site is a Köthen one.',
  })
  site!: 'koethen' | 'bernburg' | 'dessau';

  @ApiProperty({
    description:
      'The sanitised long description as PLAIN TEXT. A search matches words, not formatting; links contribute their label, images nothing.',
  })
  descriptionText!: string;

  @ApiProperty({ type: String, nullable: true }) generalEmail!: string | null;
  @ApiProperty({ type: String, nullable: true }) phone!: string | null;
  @ApiProperty({ type: String, nullable: true }) website!: string | null;
  @ApiProperty({ type: String, nullable: true }) appointmentBookingUrl!: string | null;
  @ApiProperty({ type: String, nullable: true }) address!: string | null;
  @ApiProperty({ type: String, nullable: true }) openingHours!: string | null;

  @ApiProperty({ type: [RoomReferenceDto] })
  rooms!: RoomReferenceDto[];

  @ApiProperty({ type: [ContactSearchPersonDto], description: 'Active persons only.' })
  persons!: ContactSearchPersonDto[];
}

export class ContactSearchIndexResponseDto {
  @ApiProperty({ type: [ContactSearchAreaDto] }) data!: ContactSearchAreaDto[];
  @ApiProperty({ type: ResponseMetaDto }) meta!: ResponseMetaDto;
}

export class ContactAreasResponseDto {
  @ApiProperty({ type: [ContactAreaListItemDto] }) data!: ContactAreaListItemDto[];
  @ApiProperty({ type: ResponseMetaDto }) meta!: ResponseMetaDto;
}

export class ContactAreaDetailResponseDto {
  @ApiProperty({ type: ContactAreaDetailDto }) data!: ContactAreaDetailDto;
  @ApiProperty({ type: ResponseMetaDto }) meta!: ResponseMetaDto;
}
