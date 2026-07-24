/* ==========================================================================
   SERENUT OS V2 - AUTH SERVICE
   ========================================================================= */

import { getAuthToken, clearAuthToken } from './api-client.js';

/**
 * Checks if the user has an active session token
 * @returns {boolean}
 */
export function isAuthenticated() {
  return !!getAuthToken();
}

/**
 * Returns the parsed user profile stored in session or local storage
 * @returns {object|null}
 */
export function getUserProfile() {
  try {
    const raw = sessionStorage.getItem('app_profile') || localStorage.getItem('app_profile');
    return raw ? JSON.parse(raw) : null;
  } catch (_) {
    return null;
  }
}

/**
 * Sets the user profile in session and local storage
 * @param {object} profile 
 */
export function setUserProfile(profile) {
  if (!profile) return;
  try {
    const json = JSON.stringify(profile);
    sessionStorage.setItem('app_profile', json);
    localStorage.setItem('app_profile', json);
  } catch (_) {}
}

/**
 * Checks if the authenticated user has a specific role
 * @param {string} role 
 * @returns {boolean}
 */
export function hasRole(role) {
  const profile = getUserProfile();
  const roles = profile?.roles || [];
  return roles.includes(role);
}

/**
 * Enforces authentication by redirecting to appropriate landing page if session invalid
 */
export function authGuard() {
  if (!isAuthenticated()) {
    clearAuthToken();
  }
}

/**
 * Enforces admin authorization by checking sysadmin role
 */
export function adminGuard() {
  authGuard();
  if (!hasRole('sysadmin')) {
    alert('Bu panele erişim yetkiniz bulunmamaktadır.');
    clearAuthToken();
  }
}

