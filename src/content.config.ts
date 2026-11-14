import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

const practiceQuestion = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('mcq'),
    question: z.string(),
    options: z.array(z.string()).min(2),
    answer: z.number().int().min(0),       // index of the correct option (0 = first)
    explanation: z.string(),
  }),
  z.object({
    type: z.literal('open'),
    question: z.string(),
    model_answer: z.string(),              // shown after the judge writes their own answer
  }),
]);

const modules = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/modules' }),
  schema: z.object({
    title: z.string(),
    order: z.number(),
    summary: z.string(),
    minutes: z.number().optional(),        // estimated time to complete
    video: z.string().optional(),          // YouTube link (unlisted is fine)
    draft: z.boolean().default(false),     // drafts are hidden from the site
    quiz: z.array(practiceQuestion).default([]),
  }),
});

export const collections = { modules };
