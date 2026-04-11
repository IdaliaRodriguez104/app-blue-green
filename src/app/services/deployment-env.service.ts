// src/app/services/deployment-env.service.ts
// Read-only service: polls /assets/env.json written by Jenkins
// The Angular app NEVER controls deployment — it only reads status.

import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { BehaviorSubject, Observable, timer } from 'rxjs';
import { switchMap, catchError, shareReplay } from 'rxjs/operators';
import { of } from 'rxjs';

export interface DeploymentEnv {
  environment: 'blue' | 'green' | string;
  version: string;
  gitCommit?: string;
  lastDeploy: string;
  health: 'healthy' | 'rollback' | 'unknown';
  buildNumber?: string;
  previousEnvironment?: string;
  note?: string;
  failedBuild?: string;
  lastFailedDeploy?: string;
}

const FALLBACK_ENV: DeploymentEnv = {
  environment: 'unknown',
  version: 'N/A',
  lastDeploy: 'N/A',
  health: 'unknown',
};

@Injectable({ providedIn: 'root' })
export class DeploymentEnvService {
  private readonly ENV_URL = '/assets/env.json';
  private readonly POLL_INTERVAL_MS = 30_000; // refresh every 30s

  private envSubject = new BehaviorSubject<DeploymentEnv>(FALLBACK_ENV);
  public env$: Observable<DeploymentEnv> = this.envSubject.asObservable();

  constructor(private http: HttpClient) {
    this.startPolling();
  }

  private startPolling(): void {
    // Poll env.json on init and every 30 seconds
    timer(0, this.POLL_INTERVAL_MS)
      .pipe(
        switchMap(() =>
          this.http.get<DeploymentEnv>(this.ENV_URL, {
            headers: { 'Cache-Control': 'no-cache' },
          }).pipe(
            catchError(() => of(FALLBACK_ENV))
          )
        )
      )
      .subscribe((env) => this.envSubject.next(env));
  }

  /** Force immediate refresh (e.g. after user clicks Refresh button) */
  refresh(): void {
    this.http.get<DeploymentEnv>(this.ENV_URL, {
      headers: { 'Cache-Control': 'no-cache' },
    }).pipe(
      catchError(() => of(FALLBACK_ENV))
    ).subscribe((env) => this.envSubject.next(env));
  }
}
