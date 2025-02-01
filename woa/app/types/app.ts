// app/types/app.ts
export interface AppEvent {
  id: number;
  timestamp: string;
  location: string;
  content: string;
  echartsOption?: any;
}

export interface Profile {
  name: string;
  image: string;
  path: string;
}

export interface UserSettings {
  [key: string]: unknown;
}

export interface Skill {
  name: string;
  type: 'databricks' | 'tool' | 'workflow';
  description: string;
  state: 'locked' | 'unlocked' | 'equipped';
}

export interface Spell {
  name: string;
  description: string;
  cooldown: number;
  state: 'locked' | 'unlocked' | 'equipped';
}

export interface Trainer {
  name: string;
  profilePath: string;
  skills: Skill[];
  spells: Spell[];
}
