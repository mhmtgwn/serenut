/* ==========================================================================
   SERENUT OS V2 - API CLIENT WRAPPER
   ========================================================================== */

const BASE_URL = '/api/v1';

function isUnifiedApp() {
  return window.location.pathname.includes('/app');
}

function isAdminApp() {
  return window.location.pathname.includes('/admin');
}

function getTokenKey() {
  if (isUnifiedApp()) {
    return 'app_token';
  }
  return isAdminApp() ? 'admin_token' : 'portal_token';
}

function getProfileKey() {
  if (isUnifiedApp()) {
    return 'app_profile';
  }
  return isAdminApp() ? 'admin_profile' : 'portal_profile';
}

/**
 * Resolves the authentication token based on current app context (portal vs admin)
 * @returns {string}
 */
export function getAuthToken() {
  return sessionStorage.getItem(getTokenKey()) || sessionStorage.getItem('app_token') || '';
}

/**
 * Saves the authentication token for the current app context
 * @param {string} token 
 */
export function setRefreshToken(token) {
  if (token) sessionStorage.setItem('app_refresh_token', token);
}

export function setAuthToken(token) {
  sessionStorage.setItem(getTokenKey(), token);
  if (isUnifiedApp()) {
    sessionStorage.setItem('portal_token', token);
    sessionStorage.setItem('admin_token', token);
  }
}

/**
 * Clears the authentication token and triggers a page refresh/redirect
 */
export function clearAuthToken() {
  [
    getTokenKey(),
    getProfileKey(),
    'app_token',
    'app_profile',
    'portal_token',
    'portal_profile',
    'admin_token',
    'admin_profile',
    'app_refresh_token'
  ].forEach((key) => sessionStorage.removeItem(key));

  if (!isAdminApp() && !isUnifiedApp()) {
    sessionStorage.removeItem('selected_plan_id');
    sessionStorage.removeItem('selected_billing_period');
    sessionStorage.removeItem('pending_download_release_id');
  }

  if (isUnifiedApp()) {
    window.location.href = '/app/';
    return;
  }

  window.location.href = isAdminApp() ? '/admin/' : '/portal/';
}

/**
 * Centralized fetch helper
 * @param {string} endpoint 
 * @param {object} options 
 * @returns {Promise<any>}
 */
export async function apiFetch(endpoint, options = {}) {
  const token = getAuthToken();
  
  const headers = {
    'Accept': 'application/json',
    ...(options.headers || {})
  };

  // Automatically inject bearer auth token if present
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  // Set Content-Type to JSON if body is a normal object
  if (options.body && typeof options.body === 'object' && !(options.body instanceof FormData) && !(options.body instanceof Blob)) {
    headers['Content-Type'] = 'application/json';
    options.body = JSON.stringify(options.body);
  }

  const url = endpoint.startsWith('http') ? endpoint : `${BASE_URL}${endpoint}`;
  
  const response = await fetch(url, {
    ...options,
    headers
  });

  // Handle unauthorized redirects
  if (response.status === 401) {
    clearAuthToken();
    throw new Error('Unauthorized');
  }

  if (!response.ok) {
    let errorData = null;
    try {
      errorData = await response.json();
    } catch (_) {
      // Response is not JSON
    }
    if (response.status === 403 && ['user_suspended', 'forbidden'].includes(errorData?.error)) {
      clearAuthToken();
    }

    const error = new Error(errorData?.message || errorData?.error?.message || `HTTP error! status: ${response.status}`);
    error.status = response.status;
    error.data = errorData;
    throw error;
  }

  // If response is a file download or blob, return the blob directly
  const contentType = response.headers.get('content-type');
  if (contentType && (contentType.includes('application/octet-stream') || contentType.includes('application/pdf') || contentType.includes('zip'))) {
    return response;
  }

  // Otherwise, return parsed JSON (or empty if status 204)
  if (response.status === 204) {
    return null;
  }
  
  return await response.json();
}
