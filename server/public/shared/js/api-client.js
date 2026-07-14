/* ==========================================================================
   SERENUT OS V2 - API CLIENT WRAPPER
   ========================================================================== */

const BASE_URL = '/api/v1';

/**
 * Resolves the authentication token based on current app context (portal vs admin)
 * @returns {string}
 */
export function getAuthToken() {
  if (window.location.pathname.includes('/admin')) {
    return sessionStorage.getItem('admin_token') || '';
  }
  return sessionStorage.getItem('portal_token') || '';
}

/**
 * Saves the authentication token for the current app context
 * @param {string} token 
 */
export function setAuthToken(token) {
  if (window.location.pathname.includes('/admin')) {
    sessionStorage.setItem('admin_token', token);
  } else {
    sessionStorage.setItem('portal_token', token);
  }
}

/**
 * Clears the authentication token and triggers a page refresh/redirect
 */
export function clearAuthToken() {
  if (window.location.pathname.includes('/admin')) {
    sessionStorage.removeItem('admin_token');
    window.location.href = '/admin/';
  } else {
    sessionStorage.removeItem('portal_token');
    window.location.href = '/portal/';
  }
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
    const error = new Error(errorData?.message || `HTTP error! status: ${response.status}`);
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
