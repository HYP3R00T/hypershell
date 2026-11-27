interface App {
  id: string;
  name: string;
  mark: string;
  color: string;
  pinned: boolean;
}

interface Notice {
  id: number;
  app: string;
  title: string;
  message: string;
  date: Date;
}

const desktop = document.querySelector<HTMLElement>("[data-desktop]");
const demo = desktop?.closest<HTMLElement>(".demo");
if (desktop && demo) initDesktop(desktop, demo);

function initDesktop(desktop: HTMLElement, demo: HTMLElement) {
  const get = <T extends HTMLElement>(selector: string) => {
    const element = desktop.querySelector<T>(selector);
    if (!element) throw new Error(`Desktop preview is missing ${selector}`);
    return element;
  };

  const apps = JSON.parse(desktop.dataset.apps ?? "[]") as App[];
  const panels = [...desktop.querySelectorAll<HTMLElement>("[data-panel]")];
  const windows = get("[data-windows]");
  const dock = get("[data-dock]");
  const results = get("[data-results]");
  const launcher = get("[data-panel='launcher']");
  const search = get<HTMLInputElement>(".launcher-search input");
  const allButton = get<HTMLButtonElement>("[data-all-apps]");
  const noticeTrigger = get<HTMLButtonElement>(".notification-trigger");
  const noticesPanel = get("[data-panel='notifications']");
  const tray = get("[data-tray]");
  const trayToggle = get<HTMLButtonElement>("[data-tray-toggle]");
  const pinGrid = get("[data-pin-grid]");
  const tabs = [...desktop.querySelectorAll<HTMLButtonElement>("[role='tab']")];
  const controls = get("[data-notch-zone]");
  const gapButton = demo.querySelector<HTMLButtonElement>("[data-gapless]");
  const menuButton = demo.querySelector<HTMLButtonElement>("[data-system-menu]");

  let currentPanel = "";
  let panelTrigger: HTMLElement | null = null;
  let notificationPinned = false;
  let notificationTimer: ReturnType<typeof setTimeout>;
  let showAll = false;
  let selectedResult = 0;
  let visibleApps: App[] = [];
  let focusedApp = "";
  let snoozed = false;
  let serial = 2;
  let month = new Date();
  const opened = new Map<string, HTMLElement>();
  let notices: Notice[] = [
    { id: 1, app: "Linear Carbon", title: "Desktop preview ready", message: "Open the notch for controls, or use the launcher to explore apps.", date: new Date() },
  ];

  function setPanel(name: string, trigger: HTMLElement | null = null) {
    const previous = currentPanel;
    currentPanel = name;
    panelTrigger = name ? trigger : null;
    controls.classList.toggle("is-open", name === "controls");
    menuButton?.setAttribute("aria-pressed", String(name === "system-menu"));
    for (const panel of panels) {
      const open = panel.dataset.panel === name;
      panel.classList.toggle("is-open", open);
      panel.inert = !open;
    }
    for (const button of desktop.querySelectorAll("[data-popup]")) {
      button.setAttribute("aria-expanded", String(button.getAttribute("data-popup") === name));
    }
    if (name !== "notifications") {
      notificationPinned = false;
      clearTimeout(notificationTimer);
    }
    if (name === "launcher" && previous !== name) {
      search.value = "";
      showAll = false;
      renderResults();
      search.focus({ preventScroll: true });
    }
    if (name === "calendar") renderCalendar();
    if (name === "pins") renderPins();
  }

  function setTray(open: boolean) {
    tray.classList.toggle("is-open", open);
    tray.inert = !open;
    trayToggle.setAttribute("aria-expanded", String(open));
    trayToggle.setAttribute("aria-label", open ? "Hide system tray" : "Show system tray");
  }

  function setGapless() {
    const enabled = desktop.classList.toggle("is-gapless");
    gapButton?.setAttribute("aria-pressed", String(enabled));
    if (enabled && currentPanel === "controls") setPanel("");
  }

  function selectTab(tab: HTMLButtonElement) {
    for (const candidate of tabs) {
      const selected = candidate === tab;
      candidate.tabIndex = selected ? 0 : -1;
      candidate.setAttribute("aria-selected", String(selected));
      const target = document.getElementById(candidate.getAttribute("aria-controls") ?? "");
      if (target) target.hidden = !selected;
    }
  }

  function appTile(app: App, className = "") {
    const button = document.createElement("button");
    button.type = "button";
    button.className = className;
    const icon = document.createElement("span");
    icon.className = "app-icon";
    icon.style.setProperty("--app-color", app.color);
    icon.setAttribute("aria-hidden", "true");
    icon.textContent = app.mark;
    button.append(icon);
    return button;
  }

  function namedTile(app: App) {
    const tile = appTile(app);
    const name = document.createElement("span");
    name.textContent = app.name;
    tile.append(name);
    return tile;
  }

  function renderDock() {
    dock.replaceChildren(...apps.filter(app => app.pinned || opened.has(app.id)).map(app => {
      const button = appTile(app, "dock-button dock-app");
      button.dataset.app = app.id;
      button.title = app.name;
      button.setAttribute("aria-label", app.name);
      button.toggleAttribute("data-running", opened.has(app.id));
      button.toggleAttribute("data-focused", focusedApp === app.id);
      return button;
    }));
  }

  function renderPins() {
    pinGrid.replaceChildren(...apps.map(app => {
      const button = namedTile(app);
      button.dataset.pin = app.id;
      button.setAttribute("aria-pressed", String(app.pinned));
      return button;
    }));
  }

  function renderResults() {
    const query = search.value.trim().toLowerCase();
    visibleApps = query ? apps.filter(app => app.name.toLowerCase().includes(query)) : showAll ? apps : [];
    const showResults = Boolean(query || showAll);
    launcher.classList.toggle("has-results", showResults);
    results.hidden = !showResults;
    allButton.setAttribute("aria-pressed", String(showAll));
    results.replaceChildren(...visibleApps.map(app => {
      const button = namedTile(app);
      button.dataset.app = app.id;
      return button;
    }));
    if (showResults && !visibleApps.length) {
      const empty = document.createElement("p");
      empty.className = "empty";
      empty.textContent = "No matching apps";
      results.append(empty);
    }
    highlightResult(0);
  }

  function highlightResult(index: number) {
    selectedResult = Math.max(0, Math.min(visibleApps.length - 1, index));
    for (const [position, tile] of [...results.children].entries()) {
      tile.classList.toggle("is-selected", position === selectedResult);
    }
  }

  function openApp(id: string) {
    const app = apps.find(entry => entry.id === id);
    if (!app) return;
    setPanel("");
    const existing = opened.get(id);
    if (existing) {
      focusedApp = id;
      renderDock();
      return;
    }

    const window = document.createElement("section");
    window.className = "demo-window";
    window.setAttribute("aria-label", `${app.name} preview window`);
    const header = document.createElement("header");
    const title = document.createElement("strong");
    title.textContent = app.name;
    const close = document.createElement("button");
    close.type = "button";
    close.dataset.closeApp = id;
    close.setAttribute("aria-label", `Close ${app.name}`);
    close.textContent = "×";
    header.append(title, close);
    const body = document.createElement("div");
    if (id === "files") {
      body.className = "window-folders";
      for (const folder of ["Documents", "Downloads", "Pictures", "Projects"]) {
        const label = document.createElement("span");
        label.textContent = folder;
        body.append(label);
      }
    } else {
      const sample: Record<string, string> = {
        terminal: "❯ omarchy theme current\nLinear Carbon",
        zed: "/* Linear Carbon */\naccent = #98b5d3",
        browser: "New tab",
        notes: "Desktop notes",
        settings: "Linear Carbon · Dark appearance",
        music: "No track playing",
        photos: "No photos in the preview",
      };
      const content = document.createElement(id === "terminal" || id === "zed" ? "code" : "p");
      content.style.whiteSpace = "pre-wrap";
      content.textContent = sample[id] ?? app.name;
      body.append(content);
    }
    window.append(header, body);

    if (opened.size === 2) closeApp(opened.keys().next().value ?? "");
    opened.set(id, window);
    windows.append(window);
    focusedApp = id;
    renderDock();
  }

  function closeApp(id: string) {
    opened.get(id)?.remove();
    opened.delete(id);
    if (focusedApp === id) focusedApp = [...opened.keys()].at(-1) ?? "";
    renderDock();
  }

  function renderNotices() {
    const list = get("[data-notification-list]");
    list.replaceChildren();
    if (!notices.length) {
      const empty = document.createElement("p");
      empty.className = "notification-empty";
      empty.textContent = "All caught up.";
      list.append(empty);
      return;
    }
    for (const notice of notices) {
      const row = document.createElement("article");
      row.className = "notification-row";
      const head = document.createElement("header");
      const app = document.createElement("span");
      app.textContent = notice.app;
      const time = document.createElement("time");
      time.textContent = formatTime(notice.date);
      const dismiss = document.createElement("button");
      dismiss.type = "button";
      dismiss.setAttribute("aria-label", `Dismiss ${notice.title}`);
      dismiss.textContent = "×";
      dismiss.dataset.dismissNotice = String(notice.id);
      head.append(app, time, dismiss);
      const title = document.createElement("strong");
      title.textContent = notice.title;
      const message = document.createElement("p");
      message.textContent = notice.message;
      row.append(head, title, message);
      list.append(row);
    }
  }

  function sendNotice() {
    notices = [{ id: serial++, app: "Linear Carbon", title: "Sample notification", message: "This is how a notification appears in the corner.", date: new Date() }, ...notices].slice(0, 4);
    renderNotices();
    if (snoozed || currentPanel && currentPanel !== "notifications") return;
    setPanel("notifications", noticeTrigger);
    if (!notificationPinned) {
      clearTimeout(notificationTimer);
      notificationTimer = setTimeout(() => {
        if (!notificationPinned && !noticesPanel.matches(":hover")) setPanel("");
      }, 1500);
    }
  }

  function hideNotifications() {
    clearTimeout(notificationTimer);
    notificationTimer = setTimeout(() => {
      if (currentPanel === "notifications" && !notificationPinned && !noticesPanel.matches(":hover") && !noticeTrigger.matches(":hover")) setPanel("");
    }, 160);
  }

  function renderCalendar() {
    const today = new Date();
    const y = month.getFullYear();
    const m = month.getMonth();
    const first = new Date(y, m, 1);
    const offset = (first.getDay() + 6) % 7;
    get("[data-month-label]").textContent = month.toLocaleDateString(undefined, { month: "long", year: "numeric" });
    const grid = get("[data-calendar-grid]");
    const cells: HTMLElement[] = [];
    function cell(text: string, className = "") {
      const element = document.createElement("span");
      element.textContent = text;
      element.className = className;
      cells.push(element);
    }
    for (const label of ["Wk", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]) cell(label, "day-muted");
    for (let i = 0; i < 42; i++) {
      const date = new Date(y, m, i - offset + 1);
      if (i % 7 === 0) cell(String(weekNumber(date)), "day-muted");
      const selected = date.toDateString() === today.toDateString();
      cell(String(date.getDate()), selected ? "day-today" : date.getMonth() !== m ? "day-muted" : "");
      if (selected) cells.at(-1)?.setAttribute("aria-current", "date");
    }
    grid.replaceChildren(...cells);
    const elapsed = today.getTime() - new Date(today.getFullYear(), 0, 1).getTime();
    const yearLength = new Date(today.getFullYear() + 1, 0, 1).getTime() - new Date(today.getFullYear(), 0, 1).getTime();
    get("[data-year-progress]").textContent = `${today.getFullYear()} · ${Math.round(elapsed / yearLength * 100)}% elapsed`;
  }

  function formatTime(date: Date) {
    return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
  }

  function updateClock() {
    const now = new Date();
    get("[data-clock]").textContent = formatTime(now);
    get("[data-date]").textContent = now.toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" }).replace(",", "");
  }

  gapButton?.addEventListener("click", setGapless);
  menuButton?.addEventListener("click", () => {
    const open = currentPanel !== "system-menu";
    setPanel(open ? "system-menu" : "", menuButton);
    if (open) get<HTMLButtonElement>(".system-commands button").focus({ preventScroll: true });
  });
  search.addEventListener("input", () => {
    showAll = false;
    renderResults();
  });
  allButton.addEventListener("click", () => {
    if (search.value) {
      search.value = "";
      showAll = true;
    } else {
      showAll = !showAll;
    }
    renderResults();
    search.focus();
  });
  search.addEventListener("keydown", event => {
    if (!visibleApps.length) return;
    const columns = getComputedStyle(results).gridTemplateColumns.split(" ").length;
    const delta: Record<string, number> = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: columns, ArrowUp: -columns };
    if (event.key === "Enter") {
      event.preventDefault();
      openApp(visibleApps[selectedResult].id);
    } else if (delta[event.key]) {
      event.preventDefault();
      highlightResult(selectedResult + delta[event.key]);
    }
  });
  for (const [index, tab] of tabs.entries()) {
    tab.addEventListener("click", () => selectTab(tab));
    tab.addEventListener("keydown", event => {
      const next = event.key === "ArrowDown" ? (index + 1) % tabs.length :
        event.key === "ArrowUp" ? (index - 1 + tabs.length) % tabs.length :
        event.key === "Home" ? 0 : event.key === "End" ? tabs.length - 1 : -1;
      if (next < 0) return;
      event.preventDefault();
      selectTab(tabs[next]);
      tabs[next].focus();
    });
  }

  desktop.addEventListener("input", event => {
    const input = event.target;
    if (!(input instanceof HTMLInputElement) || input.type !== "range") return;
    const output = input.closest("label")?.querySelector("output");
    if (output) output.textContent = `${input.value}%`;
    if (input.hasAttribute("data-brightness")) desktop.style.setProperty("--wallpaper-brightness", String(.24 + .76 * input.valueAsNumber / 100));
  });

  noticeTrigger.addEventListener("pointerenter", event => {
    if (event.pointerType === "touch" || currentPanel && currentPanel !== "notifications") return;
    clearTimeout(notificationTimer);
    setPanel("notifications", noticeTrigger);
  });
  noticeTrigger.addEventListener("pointerleave", hideNotifications);
  noticesPanel.addEventListener("pointerenter", () => clearTimeout(notificationTimer));
  noticesPanel.addEventListener("pointerleave", hideNotifications);

  desktop.addEventListener("contextmenu", event => {
    if (!(event.target instanceof Element) || !event.target.closest(".taskbar")) return;
    event.preventDefault();
    setPanel("panel-menu", get("[data-popup='launcher']"));
    get<HTMLButtonElement>("[data-popup='pins']").focus({ preventScroll: true });
  });

  desktop.addEventListener("click", event => {
    if (!(event.target instanceof Element)) return;
    const target = event.target;
    const button = target.closest<HTMLButtonElement>("button");
    if (!target.closest(".dock-tools") && !target.closest(".tray-menu")) setTray(false);

    if (button?.dataset.popup) {
      const name = button.dataset.popup;
      if (name === "notifications") {
        const close = currentPanel === name && notificationPinned;
        setPanel(close ? "" : name, button);
        notificationPinned = !close;
        if (notificationPinned && event.detail === 0) get<HTMLButtonElement>("[data-dnd]").focus();
      } else {
        const trigger = button.closest(".system-menu") ? menuButton : button;
        setPanel(currentPanel === name ? "" : name, trigger);
      }
      return;
    }

    if (button?.hasAttribute("data-close-panel")) {
      setPanel("");
    } else if (button?.dataset.app) {
      openApp(button.dataset.app);
    } else if (button?.dataset.closeApp) {
      closeApp(button.dataset.closeApp);
    } else if (button?.dataset.pin) {
      const app = apps.find(entry => entry.id === button.dataset.pin);
      if (app) {
        app.pinned = !app.pinned;
        button.setAttribute("aria-pressed", String(app.pinned));
        renderDock();
      }
    } else if (button?.hasAttribute("data-tray-toggle")) {
      setTray(tray.inert);
      setPanel("");
    } else if (button?.hasAttribute("data-vpn")) {
      const connected = button.getAttribute("aria-pressed") !== "true";
      button.setAttribute("aria-pressed", String(connected));
      button.textContent = connected ? "Disconnect VPN" : "Connect VPN";
    } else if (button?.hasAttribute("data-dnd")) {
      snoozed = !snoozed;
      button.setAttribute("aria-pressed", String(snoozed));
    } else if (button?.hasAttribute("data-clear")) {
      notices = [];
      renderNotices();
    } else if (button?.dataset.dismissNotice) {
      notices = notices.filter(notice => notice.id !== Number(button.dataset.dismissNotice));
      renderNotices();
    } else if (button?.dataset.month) {
      month = new Date(month.getFullYear(), month.getMonth() + Number(button.dataset.month), 1);
      renderCalendar();
    } else if (button?.hasAttribute("data-today")) {
      month = new Date();
      renderCalendar();
    } else if (button?.hasAttribute("data-toggle")) {
      button.setAttribute("aria-pressed", String(button.getAttribute("aria-pressed") !== "true"));
    } else if (button?.closest("[data-segments]")) {
      for (const option of button.parentElement?.querySelectorAll("button") ?? []) option.setAttribute("aria-pressed", String(option === button));
    } else if (currentPanel && !target.closest(".popup")) {
      setPanel("");
    }

    if (currentPanel === "notifications" && target.closest(".notification-panel")) notificationPinned = true;
  });

  demo.addEventListener("click", event => {
    if (event.target instanceof Element && event.target.closest("[data-sample-notification]")) {
      if (currentPanel !== "notifications") setPanel("");
      sendNotice();
    }
  });

  document.addEventListener("click", event => {
    if (event.target instanceof Node && !demo.contains(event.target)) {
      setPanel("");
      setTray(false);
    }
  });

  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && (currentPanel || !tray.inert)) {
      event.preventDefault();
      const trigger = panelTrigger;
      setPanel("");
      setTray(false);
      trigger?.focus({ preventScroll: true });
    } else if (event.key === "Backspace" && event.shiftKey && (event.metaKey || event.ctrlKey) &&
      event.target instanceof Node && demo.contains(event.target)) {
      event.preventDefault();
      setGapless();
    }
  });

  renderDock();
  renderNotices();
  renderCalendar();
  updateClock();
  setInterval(updateClock, 15000);
}

function weekNumber(date: Date) {
  const thursday = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  thursday.setUTCDate(thursday.getUTCDate() + 4 - (thursday.getUTCDay() || 7));
  const start = new Date(Date.UTC(thursday.getUTCFullYear(), 0, 1));
  return Math.ceil(((thursday.getTime() - start.getTime()) / 86400000 + 1) / 7);
}
