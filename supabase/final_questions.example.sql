-- Example final-test questions, for trying the site out.
-- In real use, add questions through the website (Admin → Final test questions)
-- so answer keys never end up in this public repo.
-- If you do keep a real SQL file, name it final_questions.sql: .gitignore keeps it out of git.

insert into public.final_questions (section, kind, position, prompt, options, answer_key, points, rubric, media_url) values
('mcq', 'mcq', 1, 'Who may deliver a reply speech?',
  '["The first or second speaker", "Any of the three speakers", "Only the third speaker", "Only the first speaker"]', '{"correct": 0}', 1, null, null),
('mcq', 'mcq', 2, 'A reply speaker points out that the other team never answered a key argument. This is:',
  '["New rebuttal, not allowed", "A new observation, allowed", "A new argument, not allowed", "Only allowed for Proposition"]', '{"correct": 1}', 1, null, null),
('mcq', 'mcq', 3, 'What is the accepted range for a substantive speech score?',
  '["50–100", "60–80", "65–75", "70–80"]', '{"correct": 1}', 1, null, null),

('debate', 'call', 1, 'Watch the debate below. Motion: This House would ban for-profit schools. Which team won?',
  '["Proposition", "Opposition"]', '{"correct": "Opposition"}', 5, null, 'https://youtu.be/REPLACE_WITH_UNLISTED_ID'),
('debate', 'scores', 2, 'Enter your speaker scores for this debate (0.5 steps).',
  '[{"label":"1st Proposition","side":"Proposition","min":60,"max":80},{"label":"2nd Proposition","side":"Proposition","min":60,"max":80},{"label":"3rd Proposition","side":"Proposition","min":60,"max":80},{"label":"Proposition Reply","side":"Proposition","min":30,"max":40},{"label":"1st Opposition","side":"Opposition","min":60,"max":80},{"label":"2nd Opposition","side":"Opposition","min":60,"max":80},{"label":"3rd Opposition","side":"Opposition","min":60,"max":80},{"label":"Opposition Reply","side":"Opposition","min":30,"max":40}]',
  '{"reference": [71, 72, 71, 35.5, 73, 72.5, 73, 36.5], "tolerance": 1.5}', 4, null, null),
('debate', 'written', 3, 'Write your reasoning for the decision as you would deliver it in an oral adjudication (about 300 words).',
  null, null, 10,
  E'8–10: clear call; identifies the 2–3 key clashes; explains how each was resolved and why the deciding clash mattered most; uses material from the debate.\n5–7: correct structure but thin comparison or weighing.\n0–4: summarises speeches without evaluating, or reasoning not based on the debate.', null),

('written', 'written', 1, 'Explain the difference between a new argument and new analysis of an existing argument at third speaker. Give an example of each.',
  null, null, 10,
  E'Look for: the independence test (could it carry the case on its own?); traceability to earlier material; correct examples; mention that new arguments at third are not credited unless announced in the case division (Sch 1 §9.3).', null);
