/* ==========================================================================
   SERENUT OS V2 - PERSISTENT STORAGE HELPERS
   ========================================================================== */

export const storage = {
  get(key, defaultValue = null) {
    try {
      const item = localStorage.getItem(key);
      return item ? JSON.parse(item) : defaultValue;
    } catch (_) {
      return defaultValue;
    }
  },

  set(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
      return true;
    } catch (_) {
      return false;
    }
  },

  remove(key) {
    try {
      localStorage.removeItem(key);
      return true;
    } catch (_) {
      return false;
    }
  },

  clear() {
    try {
      localStorage.clear();
      return true;
    } catch (_) {
      return false;
    }
  },

  session: {
    get(key, defaultValue = null) {
      try {
        const item = sessionStorage.getItem(key);
        return item ? JSON.parse(item) : defaultValue;
      } catch (_) {
        return defaultValue;
      }
    },

    set(key, value) {
      try {
        sessionStorage.setItem(key, JSON.stringify(value));
        return true;
      } catch (_) {
        return false;
      }
    },

    remove(key) {
      try {
        sessionStorage.removeItem(key);
        return true;
      } catch (_) {
        return false;
      }
    },

    clear() {
      try {
        sessionStorage.clear();
        return true;
      } catch (_) {
        return false;
      }
    }
  }
};
