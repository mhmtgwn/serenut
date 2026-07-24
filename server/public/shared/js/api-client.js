/* ==========================================================================
   SERENUT OS V2 - API CLIENT WRAPPER
   ========================================================================== */

const BASE_URL = '/api/v1';

/**
 * Resolves the authentication token from sessionStorage or localStorage
 * @returns {string}
 */
export function getAuthToken() {
  return sessionStorage.getItem('app_token') || localStorage.getItem('app_token') || '';
}

/**
 * Saves the refresh token
 * @param {string} token 
 */
export function setRefreshToken(token) {
  if (!token) return;
  try {
    sessionStorage.setItem('app_refresh_token', token);
    localStorage.setItem('app_refresh_token', token);
  } catch (_) {}
}

let refreshPromise = null;

async function refreshAccessToken() {
  if (refreshPromise) return refreshPromise;
  const refreshToken = sessionStorage.getItem('app_refresh_token') || localStorage.getItem('app_refresh_token');
  if (!refreshToken) return false;
  refreshPromise = fetch(`${BASE_URL}/auth/refresh`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
    body: JSON.stringify({ refresh_token: refreshToken })
  }).then(async (response) => {
    if (!response.ok) return false;
    const data = await response.json();
    setAuthToken(data.access_token);
    setRefreshToken(data.refresh_token || refreshToken);
    return true;
  }).catch(() => false).finally(() => {
    refreshPromise = null;
  });
  return refreshPromise;
}

/**
 * Saves the access token to session and local storage
 * @param {string} token 
 */
export function setAuthToken(token) {
  if (!token) return;
  try {
    sessionStorage.setItem('app_token', token);
    localStorage.setItem('app_token', token);
  } catch (_) {}
}

/**
 * Clears the authentication token and profile session
 */
export function clearAuthSession() {
  const refreshToken = sessionStorage.getItem('app_refresh_token') || localStorage.getItem('app_refresh_token');
  if (refreshToken) {
    fetch('/api/v1/auth/logout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: refreshToken })
    }).catch(() => {});
  }
  const keys = ['app_token', 'app_profile', 'app_refresh_token', 'portal_token', 'portal_profile', 'admin_token', 'admin_profile', 'selected_plan_id', 'selected_billing_period', 'pending_download_release_id'];
  keys.forEach((key) => {
    try {
      sessionStorage.removeItem(key);
      localStorage.removeItem(key);
    } catch (_) {}
  });
}

export function clearAuthToken() {
  clearAuthSession();
  if (window.location.pathname.startsWith('/app')) {
    window.location.href = '/app/';
  } else {
    window.location.href = '/app/';
  }
}

/**
 * Centralized fetch helper
 * @param {string} endpoint 
 * @param {object} options 
 * @returns {Promise<any>}
 */
export async function apiFetch(endpoint, options = {}, retry = true) {
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
    if (retry && await refreshAccessToken()) {
      const retryOptions = { ...options };
      if (typeof retryOptions.body === 'string' && headers['Content-Type'] === 'application/json') {
        try { retryOptions.body = JSON.parse(retryOptions.body); } catch (_) {}
      }
      return apiFetch(endpoint, retryOptions, false);
    }
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
    if (response.status === 403 && errorData?.error === 'user_suspended') {
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
