// app/infrastructure/LocalAuthService.ts
interface LocalUser {
  userId: string;
  name: string;
  email: string;
  roles: string[];
}

export class LocalAuthService {
  private static instance: LocalAuthService;
  private currentUser: LocalUser | null = null;

  private constructor() {
    // Initialize with stored user if exists
    const stored = localStorage.getItem('local_auth_user');
    if (stored) {
      this.currentUser = JSON.parse(stored);
    }
  }

  static getInstance(): LocalAuthService {
    if (!LocalAuthService.instance) {
      LocalAuthService.instance = new LocalAuthService();
    }
    return LocalAuthService.instance;
  }

  isAuthenticated(): boolean {
    return !!this.currentUser;
  }

  getCurrentUser(): LocalUser | null {
    return this.currentUser;
  }

  async login(email: string = 'dev@localhost'): Promise<void> {
    // Create a development user
    this.currentUser = {
      userId: `dev-${Math.random().toString(36).substring(7)}`,
      name: 'Development User',
      email,
      roles: ['authenticated-user']
    };

    localStorage.setItem('local_auth_user', JSON.stringify(this.currentUser));
  }

  async logout(): Promise<void> {
    this.currentUser = null;
    localStorage.removeItem('local_auth_user');
  }
}