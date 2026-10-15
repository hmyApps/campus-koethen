import { ApiProperty } from '@nestjs/swagger';
import { ResponseMetaDto } from '../../common/dto/meta.dto';
import { PriceGroup } from './meine-mensa.schema';
import { MEAL_ALLERGENS, MEAL_TRAITS, MealAllergen, MealTrait } from './meal-semantics';

/**
 * Public shapes for /v1/canteens*.
 *
 * There is deliberately NO image field anywhere in this file: canteen images
 * are not used by this project, and the upstream `image_url` is dropped during
 * import rather than merely hidden here.
 */

export class CanteenRefDto {
  @ApiProperty({ example: 'koethen-fasanerieallee' }) slug!: string;

  @ApiProperty({ example: 'Mensa Köthen', description: 'API-owned text, available in de and en.' })
  displayName!: string;

  @ApiProperty({ example: 'Fasanerieallee' }) campusLabel!: string;

  @ApiProperty({
    enum: ['koethen', 'bernburg', 'dessau'],
    example: 'koethen',
    description: "Campus site of the canteen. The app lists the reader's own site first.",
  })
  site!: 'koethen' | 'bernburg' | 'dessau';
}

export class CanteenListItemDto extends CanteenRefDto {
  @ApiProperty({
    type: String,
    nullable: true,
    format: 'date-time',
    description: 'Null means the canteen has never synchronised successfully.',
  })
  lastSuccessfulSyncAt!: string | null;

  @ApiProperty({ description: 'True when the data is older than the configured threshold.' })
  dataStale!: boolean;
}

export class MealMarkerDto {
  @ApiProperty({ example: '52' }) code!: string;

  @ApiProperty({
    example: 'vegan',
    description: 'German label from the source — never machine-translated.',
  })
  label!: string;

  @ApiProperty({
    enum: ['ingredient', 'marker'],
    description:
      'The source mixes both namespaces inside one array, so the distinction is preserved here.',
  })
  kind!: 'ingredient' | 'marker';
}

export class MealPriceDto {
  @ApiProperty({
    enum: ['student', 'employee', 'guest'],
    description: 'Stable technical key. The client highlights "student".',
  })
  group!: PriceGroup;

  @ApiProperty({ example: 'Studierende', description: 'Localised, API-owned label.' })
  label!: string;

  @ApiProperty({
    example: '1.95',
    description: 'Decimal STRING with fixed scale — never a float, to avoid rounding.',
  })
  amount!: string;

  @ApiProperty({ example: 'EUR' }) currency!: 'EUR';
}

export class MealDto {
  @ApiProperty({ example: '58033' }) id!: string;
  @ApiProperty({ example: 'Bulgur-Pfanne' }) name!: string;
  @ApiProperty({ type: String, nullable: true }) subtitle!: string | null;

  @ApiProperty({
    enum: ['de'],
    description: 'Always "de": the upstream source publishes German only and is not translated.',
  })
  sourceLanguage!: 'de';

  @ApiProperty({ type: Number, nullable: true }) counterId!: number | null;
  @ApiProperty() isSprint!: boolean;
  @ApiProperty({ type: [String] }) extras!: string[];
  @ApiProperty({
    type: [MealMarkerDto],
    description:
      'Everything the source declared, including codes with no semantic meaning to this API.',
  })
  markers!: MealMarkerDto[];

  @ApiProperty({
    enum: MEAL_TRAITS,
    isArray: true,
    description:
      'Stable semantic properties of the dish, derived from the source. Filter on these, never on marker codes or labels.',
  })
  traits!: MealTrait[];

  @ApiProperty({
    enum: MEAL_ALLERGENS,
    isArray: true,
    description:
      'Declared allergens as stable keys. A subtype (e.g. "gluten_wheat") always comes with its parent ("gluten"). A marker the API cannot classify appears in `markers` only and never gets an invented key.',
  })
  allergens!: MealAllergen[];

  @ApiProperty({
    type: [MealPriceDto],
    description: 'All groups the source provided. A missing group is absent, never estimated.',
  })
  prices!: MealPriceDto[];
}

export class CanteenDayDto {
  @ApiProperty({ example: '2026-07-20' }) date!: string;

  @ApiProperty({
    type: [MealDto],
    description: 'An empty array is a real day without meals, not a loading failure.',
  })
  meals!: MealDto[];
}

export class CanteenMenuDto {
  @ApiProperty({ type: CanteenRefDto }) canteen!: CanteenRefDto;

  @ApiProperty({ type: [CanteenDayDto], description: 'Every day of the requested range.' })
  days!: CanteenDayDto[];
}

export class CanteensResponseDto {
  @ApiProperty({ type: [CanteenListItemDto] }) data!: CanteenListItemDto[];
  @ApiProperty({ type: ResponseMetaDto }) meta!: ResponseMetaDto;
}

export class CanteenMenuResponseDto {
  @ApiProperty({ type: CanteenMenuDto }) data!: CanteenMenuDto;
  @ApiProperty({ type: ResponseMetaDto }) meta!: ResponseMetaDto;
}
