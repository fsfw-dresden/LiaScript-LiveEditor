<script lang="ts">
import { tutorial } from "../ts/Tutorial";
import Dexie from "../ts/indexDB";

import Editor from "../components/Editor.vue";
import Preview from "../components/Preview.vue";
import Modal from "../components/Modal.vue";
import TableInsertDropdown from "../components/TableInsertDropdown.vue";
import { compress } from "shrink-string";

import pako from "pako";
import JSZip from "jszip";

import { Splitpanes, Pane } from "splitpanes";
import "splitpanes/dist/splitpanes.css";

import { LiaScriptURL } from "../ts/utils";

// @ts-ignore
// import JSONWorker from "url:monaco-editor/esm/vs/language/json/json.worker.js";
// @ts-ignore
// import CSSWorker from "url:monaco-editor/esm/vs/language/css/css.worker.js";
// @ts-ignore
// import HTMLWorker from "url:monaco-editor/esm/vs/language/html/html.worker.js";
// @ts-ignore
// import TSWorker from "url:monaco-editor/esm/vs/language/typescript/ts.worker.js";
// @ts-ignore
import EditorWorker from "url:monaco-editor/esm/vs/editor/editor.worker.js";
import { editor } from "monaco-editor";

// @ts-ignore
window.MonacoEnvironment = {
  getWorkerUrl: function (moduleId, label) {
    /*
    if (label === "json") {
      return JSONWorker;
    }
    if (label === "css" || label === "scss" || label === "less") {
      return CSSWorker;
    }
    if (label === "html" || label === "handlebars" || label === "razor") {
      return HTMLWorker;
    }
    if (label === "typescript" || label === "javascript") {
      return TSWorker;
    }
    */
    return EditorWorker;
  },
};

type SyncedFileHash = string;

type SyncedFiles = {
  [key: string]: SyncedFileHash;
}

export default {
  name: "LiaScript",

  props: ["storageId", "content", "initialContent", "fileUrl", "connection", "embed", "mode", "enableSync"],

  data() {
    let database: Dexie | undefined;

    if (this.$props.storageId) {
      database = new Dexie();
      database.maybeInit(this.$props.storageId);

      const self = this;
      database.watch(this.$props.storageId, (meta) => {
        self.meta = meta;
      });
    }

    let connectionType = this.$props.connection || "offline";

    switch (connectionType) {
      case "webrtc":
        connectionType = "WebRTC";
        break;
      case "websocket":
        connectionType = "WebSocket";
        break;
      default:
        connectionType = "Offline";
    }

    return {
      preview: undefined,
      horizontal:
        document.documentElement.clientWidth < document.documentElement.clientHeight,
      previewNotReady: true,
      compilationCounter: 0,
      mode: this.$props.mode || 0,
      editorIsReady: false,
      database,
      meta: {},
      onlineUsers: 0,
      lights: false,
      showLabels: false,
      autoCompile: true,
      autoPublish: false,
      conn: {
        type: connectionType,
        users: 0,
      },
      resizing: false,
      LiaScriptURL,
      debouncedCompile: null,
      debouncedPublish: null,
      localFileSyncServer: "http://localhost:9000/sync",
      syncedFiles: {},
      enableSync: this.$props.enableSync || false,
    };
  },

  computed: {
    lightMode() {
      return this.lights ? "bi bi-sun" : "bi bi-moon";
    },
  },

  mounted() {
    window.addEventListener("resize", () => {
      this.horizontal =
        document.documentElement.clientWidth < document.documentElement.clientHeight;
    });
  },

  methods: {
    createDebounce(func: Function, wait: number) {
      let timeout: NodeJS.Timeout | null = null;

      return function (...args: any[]) {
        if (timeout) {
          clearTimeout(timeout);
        }

        timeout = setTimeout(() => {
          func.apply(this, args);
        }, wait);
      };
    },

    urlPath(path: string[]) {
      return window.location.origin + window.location.pathname + "?/" + path.join("/");
    },

    online(users: number) {
      this.conn.users = users;
    },

    changeMode(mode: number) {
      this.mode = mode;
    },

    shareLink() {
      this.$refs.modal.show(
        "Collaboration link",
        `
        If you share the link below, the editor will be in collaborative mode.
        Working should also be possible offline, but all connected users will work on the same course.
        If you did receive this via a collaboration link and want to make a complete new course by yourself, then you will have to click onto the "Fork" button, which will create a complete new version.

        <hr>

        <a target="_blank" href="${window.location.toString()}">
          ${window.location.toString()}
        </a>`
      );
    },

    shareFile() {
      const fileUrl = prompt(
        "please insert the URL of a Markdown file you want to share",
        ""
      );

      if (!fileUrl) return;

      this.$refs.modal.show(
        "External resource",
        `
        Use this URL to predefine the content for your share link.
        In this case the editor will at first try to load the Markdown file and insert its content into the editor.
        This link will only work if your Markdown file is accessible via the internet.

        <hr>

        <a target="_blank" style="word-break: break-all" href="${this.urlPath([
          "show",
          "file",
          fileUrl,
        ])}">
          ${this.urlPath(["show", "file", fileUrl])}
        </a>`
      );
    },

    bytesInfo(url: string) {
      return `<code>URL-length: ${url.length} bytes</code><br>`;
    },

    async shareData() {
      let base64 = "";

      let uriEncode = "";
      let gzip = "";

      try {
        base64 =
          LiaScriptURL + "?data:text/plain;base64," + btoa(this.$refs.editor.getValue());

        base64 =
          this.bytesInfo(base64) +
          `<a target="_blank" style="word-break: break-all" href="${base64}">
          ${base64}
        </a>`;
      } catch (e) { }

      try {
        uriEncode =
          LiaScriptURL +
          "?data:text/plain," +
          encodeURIComponent(this.$refs.editor.getValue());

        uriEncode =
          this.bytesInfo(uriEncode) +
          `<a target="_blank" style="word-break: break-all" href="${uriEncode}">
          ${uriEncode}
        </a>`;
      } catch (e) { }

      try {
        gzip = pako.gzip(this.$refs.editor.getValue());
        gzip =
          LiaScriptURL +
          "?data:text/plain;charset=utf-8;Content-Encoding=gzip;base64," +
          btoa(String.fromCharCode.apply(null, gzip));

        gzip =
          this.bytesInfo(gzip) +
          `<a target="_blank" style="word-break: break-all" href="${gzip}">
          ${gzip}
        </a>`;
      } catch (e) { }

      this.$refs.modal.show(
        "Data-Protocol",
        `
        The entire content of the course is base64 encoded or URI-encoded put into a data-URI.
        Since base64 might fail for certain languages, the URI-encoded URL is generated as well.
        However, this works only for short courses, the longer the course the longer the URi.
        Sharing your editor via a messenger for example, you will have to check first if no parts are truncated!
        Additionally different browser support different lengths of URLs... (Choose the shorter version)

        <hr>

        ${gzip}

        <hr>

        ${base64}

        <hr>

        ${uriEncode}
        `
      );
    },

    async shareCode() {
      const zipCode = this.urlPath([
        "show",
        "code",
        await compress(this.$refs.editor.getValue()),
      ]);

      this.$refs.modal.show(
        "Snapshot url",
        `
        Snapshots are URLs that contain the entire course defintion.
        However, this works only for short courses, the longer the course the longer the URL.
        Sharing your editor via a messenger for example, you will have to check first if no parts are truncated!
        Additionally different browser support different lengths of URLs...

        <hr>
        ${this.bytesInfo(zipCode)}
        <a target="_blank" style="word-break: break-all" href="${zipCode}">
          ${zipCode}
        </a>`
      );
    },

    async embedCode() {
      const zipCode = this.urlPath([
        "embed",
        "code",
        await compress(this.$refs.editor.getValue()),
      ]);

      const base64 = this.urlPath([
        "embed",
        "code",
        btoa(unescape(encodeURIComponent(this.$refs.editor.getValue()))),
      ]);

      this.$refs.modal.show(
        "Embed Code",
        `
        Copy this HTML code into your website to embed the this as an example.
        Optionally you can modify the URL with one of the following, to open the editor or the preview directly:<br>

        <code>?/embed/code/edit</code> or <code>?/embed/code/preview</code>
W
        <hr>

        ${this.bytesInfo(zipCode)}
        <code style="word-break: break-all">&lt;iframe style="height: 80vh; min-width: 100%; border: 1px black solid" src="${zipCode}"&gt;&lt;/iframe&gt;</code>

        <hr>
        <p>
          This code can be generated externally via:
          <code>btoa(unescape(encodeURIComponent(string)))</code>
        </p>

        ${this.bytesInfo(base64)}
        <code style="word-break: break-all">&lt;iframe style="height: 80vh; min-width: 100%; border: 1px black solid" src="${base64}"&gt;&lt;/iframe&gt;</code>
        `
      );
    },

    download() {
      const element = document.createElement("a");
      element.setAttribute(
        "href",
        "data:text/plain;charset=utf-8," +
        encodeURIComponent(this.$refs.editor.getValue())
      );
      element.setAttribute("download", "README.md");
      element.style.display = "none";
      document.body.appendChild(element);
      element.click();
      document.body.removeChild(element);
    },

    downloadZip() {
      const zip = JSZip();

      zip.file("README.md", this.$refs.editor.getValue());

      const blobs = this.$refs.editor.getAllBlobs();

      if (blobs) {
        for (const blob of blobs) {
          zip.file(blob.name, blob.data);
        }
      }

      const fileName =
        "Project-" + (this.$props?.storageId?.slice(0, 8) || "xxxxxxxx") + ".zip";
      zip.generateAsync({ type: "blob" }).then(function (content) {
        let url = URL.createObjectURL(content);

        const element = document.createElement("a");
        element.href = url;
        element.setAttribute("download", fileName);
        element.style.display = "none";
        document.body.appendChild(element);
        element.click();
        document.body.removeChild(element);
        element.addEventListener("click", function () {
          setTimeout(() => URL.revokeObjectURL(url), 30 * 1000);
        });
      });
    },

    async syncViaHttp() {
      const documentId = this.$props.storageId || "defaultDocument"; // Use storageId or a default name
      const currentContent = this.$refs.editor.getValue();
      const currentHash = await this.hashContent(currentContent);

      // Check if the content has changed
      if (this.syncedFiles['content'] === currentHash) {
        console.log("No changes detected, skipping sync.");
        return; // No changes, skip sync
      }

      type HTTPSyncRequestData = {
        documentId: string;
        fileName: string;
        fileContent: string;
        blobs: {
          [key: string]: string;
        };
      }

      // Prepare the data to send
      const data: HTTPSyncRequestData = {
        documentId: documentId,
        fileName: "document.md", // You can customize this as needed
        fileContent: currentContent,
        blobs: {},
      };

      const uint8ArrayToBase64 = (array: Uint8Array): string => {
        let binary = '';
        for (let i = 0; i < array.length; i++) {
          binary += String.fromCharCode(array[i]);
        }
        return btoa(binary);
      }

      // Track new hashes to update only after successful sync
      const newHashes: { [key: string]: string } = {
        content: currentHash
      };

      // Include blobs
      const blobs = this.$refs.editor.getAllBlobs();
      for (const blob of blobs) {
        const blobHash = await this.hashContent(blob.data);
        if (this.syncedFiles[blob.name] !== blobHash) {
          console.log("Blob changed:", blob.name);
          newHashes[blob.name] = blobHash; // Track new hash
          data.blobs[blob.name] = uint8ArrayToBase64(blob.data); // Add blob data to the request
        } else {
          console.log("Blob unchanged:", blob.name);
        }
      }

      // Send the data via POST request
      try {
        const response = await fetch(this.localFileSyncServer, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(data),
        });

        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }

        // Only update hashes after successful sync
        Object.assign(this.syncedFiles, newHashes);
        const result = await response.json();
        console.log("Sync successful");
        if (result.fileContent) {
          this.$refs.editor.clearAllBlobs();
          this.$refs.editor.setValue(result.fileContent);
        }
      } catch (error) {
        console.error("Error syncing data:", error);
      }
    },

    async hashContent(content: string) {
      const encoder = new TextEncoder();
      const data = encoder.encode(content);
      const hashBuffer = await crypto.subtle.digest('SHA-256', data);
      const hashArray = Array.from(new Uint8Array(hashBuffer));
      return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
    },

    fork() {
      this.$refs.editor.fork();
    },

    switchLights() {
      this.lights = this.$refs.editor.switchLights();
    },

    compile() {
      console.log("liascript: compile");

      if (this.preview && this.editorIsReady) {
        let code = this.$refs.editor.getValue();

        if (code.trim().length == 0) {
          code = tutorial;
        }

        this.preview.focusOnMain = false;
        this.preview.scrollUpOnMain = false;

        this.preview.jit(code);
      }
    },

    fetchError(src: string) {
      return this.$refs.editor.getBlob(src);
    },

    editorReady() {
      console.log("liascript: editor ready");
      this.editorIsReady = true;
      this.lights = this.$refs.editor.lights;
      if (this.$props.initialContent) {
        console.log("liascript: initContent");
        this.$refs.editor.initContent(this.$props.initialContent);
      }
      this.debouncedCompile = this.createDebounce(() => {
        if (this.autoCompile) {
          this.compile();
        }
      }, 1000);
      this.debouncedPublish = this.createDebounce(() => {
        if (this.autoPublish) {
          this.syncViaHttp();
        }
      }, 3000);
      this.$refs.editor.onChange(this.debouncedCompile);
      this.$refs.editor.onChange(this.debouncedPublish);
      this.compile();
    },

    previewReady(preview: any) {
      console.log("liascript: preview ready");
      this.preview = preview;
      this.compile();
    },

    gotoEditor(line: number) {
      if (this.$refs.editor) {
        this.$refs.editor.gotoLine(line);
      }
    },

    gotoPreview(line: number) {
      if (this.preview) this.preview.gotoLine(line);
    },

    previewUpdate(params: any) {
      console.log("liascript: update");

      this.compilationCounter++;
      if (this.compilationCounter > 1) {
        this.previewNotReady = false;

        if (this.$props.storageId) {
          const titleMatch = this.$refs.editor.getValue().match(/^# (.+)/m);

          if (titleMatch) params.title = titleMatch[1];

          this.database.put(this.$props.storageId, params);
        }
      }
    },
  },

  components: { Editor, Modal, Pane, Preview, Splitpanes, TableInsertDropdown },
};
</script>

<template>
  <nav class="navbar navbar-expand-lg bg-light">
    <div style="display: flex; flex-direction: column; width: 100%;">
      <ul class="nav nav-tabs" id="editorTabs" role="tablist">
        <li class="nav-item" role="presentation">
          <button class="nav-link active" id="format-tab" data-bs-toggle="tab" data-bs-target="#format" type="button"
            role="tab" aria-controls="format" aria-selected="true">
            <i class="bi bi-type"></i> Formatting
          </button>
        </li>
        <li class="nav-item" role="presentation">
          <button class="nav-link" id="insert-tab" data-bs-toggle="tab" data-bs-target="#insert" type="button"
            role="tab" aria-controls="insert" aria-selected="false">
            <i class="bi bi-plus-square"></i> Insert
          </button>
        </li>
        <li class="nav-item" role="presentation">
          <button class="nav-link" id="view-tab" data-bs-toggle="tab" data-bs-target="#view" type="button" role="tab"
            aria-controls="view" aria-selected="false">
            <i class="bi bi-eye"></i> View
          </button>
        </li>
        <li class="nav-item" role="presentation">
          <button class="nav-link" id="record-tab" data-bs-toggle="tab" data-bs-target="#record" type="button"
            role="tab" aria-controls="record" aria-selected="false">
            <i class="bi bi-record-circle"></i> Recording
          </button>
        </li>
        <li class="nav-item" role="presentation">
          <button class="nav-link" id="options-tab" data-bs-toggle="tab" data-bs-target="#options" type="button"
            role="tab" aria-controls="options" aria-selected="false">
            <i class="bi bi-gear"></i> Options
          </button>
        </li>
        <li class="nav-item" role="presentation">
          <button class="nav-link" id="advanced-elements-tab" data-bs-toggle="tab" data-bs-target="#advanced-elements"
            type="button" role="tab" aria-controls="advanced-elements" aria-selected="false">
            <i class="bi bi-plus-square"></i> Advanced Elements
          </button>
        </li>
        <li class="nav-item" role="presentation">
          <button class="nav-link" id="file-tab" data-bs-toggle="tab" data-bs-target="#file" type="button" role="tab"
            aria-controls="file" aria-selected="false">
            <i class="bi bi-save"></i> File
          </button>
        </li>
        <li class="nav-item ms-auto" role="presentation">
          <div class="form-check form-switch pt-2 pe-3">
            <input class="form-check-input" type="checkbox" role="switch" id="showLabelsSwitch" v-model="showLabels">
            <label class="form-check-label" for="showLabelsSwitch">
              Show Labels
            </label>
          </div>
        </li>
      </ul>
      <div class="tab-content p-2 border-bottom" id="editorTabContent">
        <div class="tab-pane fade show active" id="format" role="tabpanel" aria-labelledby="format-tab">
          <div class="btn-toolbar" role="toolbar">

            <!-- Font Group -->
            <div class="btn-group me-2" role="group" aria-label="Font">
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('bold')"
                title="Bold">
                <i class="bi bi-type-bold"></i>
                <div v-if="showLabels">Bold</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('italic')"
                title="Italic">
                <i class="bi bi-type-italic"></i>
                <div v-if="showLabels">Italic</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary"
                @click="$refs.editor?.make('strikethrough')" title="Strikethrough">
                <i class="bi bi-type-strikethrough"></i>
                <div v-if="showLabels">Strikethrough</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('underline')"
                title="Underline">
                <i class="bi bi-type-underline"></i>
                <div v-if="showLabels">Underline</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('superscript')"
                title="Superscript">
                <i class="bi bi-superscript"></i>
                <div v-if="showLabels">Superscript</div>
              </button>
            </div>

            <div class="btn-group me-2" role="group" aria-label="Heading">
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('header')"
                title="Heading">
                <i class="bi bi-type-h1"></i>
                <div v-if="showLabels">Heading</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary dropdown-toggle dropdown-toggle-split"
                data-bs-toggle="dropdown" aria-expanded="false">
                <span class="visually-hidden">Toggle Dropdown</span>
              </button>
              <ul class="dropdown-menu">
                <li><button class="dropdown-item" @click="$refs.editor?.make('header', 1)">Heading 1</button></li>
                <li><button class="dropdown-item" @click="$refs.editor?.make('header', 2)">Heading 2</button></li>
                <li><button class="dropdown-item" @click="$refs.editor?.make('header', 3)">Heading 3</button></li>
                <li><button class="dropdown-item" @click="$refs.editor?.make('header', 4)">Heading 4</button></li>
                <li><button class="dropdown-item" @click="$refs.editor?.make('header', 5)">Heading 5</button></li>
                <li><button class="dropdown-item" @click="$refs.editor?.make('header', 6)">Heading 6</button></li>
              </ul>
            </div>


            <!-- Paragraph Group -->
            <div class="btn-group me-2" role="group" aria-label="Paragraph">
              <button type="button" class="btn btn-sm btn-outline-secondary"
                @click="$refs.editor?.make('list-unordered')" title="Bullet List">
                <i class="bi bi-list-ul"></i>
                <div v-if="showLabels">Bullet List</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('list-ordered')"
                title="Numbered List">
                <i class="bi bi-list-ol"></i>
                <div v-if="showLabels">Numbered List</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('list-check')"
                title="Check List">
                <i class="bi bi-check-square"></i>
                <div v-if="showLabels">Check List</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('quote')"
                title="Quote">
                <i class="bi bi-quote"></i>
                <div v-if="showLabels">Quote</div>
              </button>
            </div>
          </div>

        </div>



        <div class="tab-pane fade" id="insert" role="tabpanel" aria-labelledby="insert-tab">
          <div class="btn-toolbar" role="toolbar">
            <!-- Tables & Illustrations -->
            <div class="btn-group me-2" role="group" aria-label="Tables & Illustrations">
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('table')"
                title="Table">
                <i class="bi bi-table"></i>
                <div v-if="showLabels">Table</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('image')"
                title="Picture">
                <i class="bi bi-image"></i>
                <div v-if="showLabels">Picture</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('graph')"
                title="Chart">
                <i class="bi bi-graph-down"></i>
                <div v-if="showLabels">Chart</div>
              </button>
            </div>

            <!--Upload-->
            <div class="btn-group" role="group" aria-label="Upload Multiline">
              <button class="btn btn-sm btn-outline-secondary" type="button" title="Upload Image"
                @click="$refs.editor?.make('upload-image')">
                <i class="bi bi-upload"></i>
                <i class="bi bi-image icon-overlay"></i>
                <div v-if="showLabels">Image Upload</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button" title="Upload Audio"
                @click="$refs.editor?.make('upload-audio')">
                <i class="bi bi-upload"></i>
                <i class="bi bi-music-note-beamed icon-overlay"></i>
                <div v-if="showLabels">Audio Upload</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button" title="Upload Movie"
                @click="$refs.editor?.make('upload-movie')">
                <i class="bi bi-upload"></i>
                <i class="bi bi-film icon-overlay"></i>
                <div v-if="showLabels">Movie Upload</div>
              </button>
            </div>


            <!-- Table -->
            <TableInsertDropdown @insert-table="$refs.editor?.make('multi-column-table', $event)"
              :showLabels="showLabels" />

            <!-- Media -->
            <div class="btn-group me-2" role="group" aria-label="Media">
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('audio')"
                title="Audio">
                <i class="bi bi-music-note-beamed"></i>
                <div v-if="showLabels">Audio</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('movie')"
                title="Video">
                <i class="bi bi-film"></i>
                <div v-if="showLabels">Video</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('oembed')"
                title="Embed Website">
                <i class="bi bi-puzzle"></i>
                <div v-if="showLabels">Embed Website</div>
              </button>
            </div>

            <!-- Links -->
            <div class="btn-group me-2" role="group" aria-label="Links">
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('link')"
                title="Link">
                <i class="bi bi-link-45deg"></i>
                <div v-if="showLabels">Link</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor?.make('line')"
                title="Horizontal Line">
                <i class="bi bi-hr"></i>
                <div v-if="showLabels">Horizontal Line</div>
              </button>
            </div>
          </div>
        </div>

        <div class="tab-pane fade" id="view" role="tabpanel" aria-labelledby="view-tab">
          <div class="btn-toolbar" role="toolbar">
            <!-- View Options -->
            <div class="btn-group me-2" role="group" aria-label="View Options">
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="changeMode(-1)"
                title="Editor Only">
                <i class="bi bi-pencil"></i>
                <div v-if="showLabels">Editor Only</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="changeMode(0)" title="Split View">
                <i class="bi bi-layout-split"></i>
                <div v-if="showLabels">Split View</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="changeMode(1)"
                title="Preview Only">
                <i class="bi bi-eye"></i>
                <div v-if="showLabels">Preview Only</div>
              </button>
            </div>

            <!-- Theme -->
            <div class="btn-group me-2" role="group" aria-label="Theme">
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="switchLights()"
                title="Toggle Theme">
                <i :class="lightMode"></i>
                <div v-if="showLabels">Toggle Theme</div>
              </button>
            </div>
          </div>
        </div>

        <div class="tab-pane fade" id="record" role="tabpanel" aria-labelledby="record-tab">
          <div class="btn-toolbar" role="toolbar">
            <!-- Recording Options -->
            <div class="btn-group me-2" role="group" aria-label="Recording Options">
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="$refs.editor.recorder.audio = true"
                title="Audio Recording">
                <i class="bi bi-mic"></i>
                <div v-if="showLabels">Audio Recording</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary"
                @click="$refs.editor.recorder.webcam = true" title="Video Recording">
                <i class="bi bi-webcam"></i>
                <div v-if="showLabels">Video Recording</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary"
                @click="$refs.editor.recorder.desktop = true" title="Screen Recording">
                <i class="bi bi-camera-reels"></i>
                <div v-if="showLabels">Screen Recording</div>
              </button>
            </div>
          </div>
        </div>

        <div class="tab-pane fade" id="options" role="tabpanel" aria-labelledby="options-tab">
          <div class="btn-toolbar" role="toolbar">
            <!-- Compile Options -->
            <div class="btn-group me-2" role="group" aria-label="Compile Options">
              <button type="button" class="btn btn-sm btn-outline-secondary" :class="{ 'active': autoCompile }"
                @click="autoCompile = !autoCompile" title="Auto Compile">
                <i :class="autoCompile ? 'bi bi-check' : 'bi bi-x'"></i>
                <div v-if="showLabels">Auto Compile</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="compile()"
                title="Compile (Ctrl+S)">
                <i class="bi bi-arrow-counterclockwise"></i>
                <div v-if="showLabels">Compile (Ctrl+S)</div>
              </button>
            </div>

            <!-- Sync Options -->
            <div class="btn-group me-2" role="group" aria-label="Sync Options">
              <button type="button" class="btn btn-sm btn-outline-secondary" @click="syncViaHttp()" title="Publish">
                <i class="bi bi-floppy"></i>
                <div v-if="showLabels">Publish</div>
              </button>
              <button type="button" class="btn btn-sm btn-outline-secondary" :class="{ 'active': autoPublish }"
                @click="autoPublish = !autoPublish" title="Auto Publish">
                <i class="bi bi-robot"></i>
                <div v-if="showLabels">Auto Publish</div>
              </button>
            </div>

          </div>
        </div>
        <!-- Advanced Elements -->
        <div class="tab-pane fade" id="advanced-elements" role="tabpanel" aria-labelledby="advanced-elements-tab">
          <div class="btn-toolbar" role="toolbar">
            <!-- Advanced Elements -->


            <div class="btn-group" role="group" aria-label="LiaScript Effects">
              <button class="btn btn-sm btn-outline-secondary" type="button" title="Animation"
                @click="$refs.editor?.make('animation')">
                <i class="bi bi-lightning-fill"></i>
                <i class="bi bi-easel icon-overlay"></i>
                <div v-if="showLabels">Animation</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button" title="Comment"
                @click="$refs.editor?.make('comment')">
                <i class="bi bi-chat-text"></i>
                <i class="bi bi-easel icon-overlay"></i>
                <div v-if="showLabels">Comment</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button" title="Speak out loud"
                @click="$refs.editor?.make('tts')">
                <i class="bi bi-play-circle"></i>
                <i class="bi bi-easel icon-overlay"></i>
                <div v-if="showLabels">Speak out loud</div>
              </button>
            </div>

            <div class="btn-group" role="group" aria-label="Quizzes">
              <button class="btn btn-sm btn-outline-secondary" type="button" title="Single Choice Quiz"
                @click="$refs.editor?.make('quiz-single-choice')">
                <i class="bi bi-x-circle"></i>
                <i class="bi bi-question-lg icon-overlay"></i>
                <div v-if="showLabels">Single Choice Quiz</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button" title="Multiple Choice Quiz"
                @click="$refs.editor?.make('quiz-multiple-choice')">
                <i class="bi bi-x-square"></i>
                <i class="bi bi-question-lg icon-overlay"></i>
                <div v-if="showLabels">Multiple Choice Quiz</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button" title="Text Input Quiz"
                @click="$refs.editor?.make('quiz-input')">
                <i class="bi bi-input-cursor-text"></i>
                <i class="bi bi-question-lg icon-overlay"></i>
                <div v-if="showLabels">Text Input Quiz</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button" title="Selection Quiz"
                @click="$refs.editor?.make('quiz-selection')">
                <i class="bi bi-option"></i>
                <i class="bi bi-question-lg icon-overlay"></i>
                <div v-if="showLabels">Selection Quiz</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button" title="Matrix Quiz"
                @click="$refs.editor?.make('quiz-matrix')">
                <i class="bi bi-grid-3x3-gap"></i>
                <i class="bi bi-question-lg icon-overlay"></i>
                <div v-if="showLabels">Matrix Quiz</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button" title="Gap Text"
                @click="$refs.editor?.make('quiz-gap-text')">
                <i class="bi bi-body-text"></i>
                <i class="bi bi-question-lg icon-overlay"></i>
                <div v-if="showLabels">Gap Text</div>
              </button>
            </div>

            <div class="btn-group" role="group" aria-label="Formulas with KaTeX">
              <button class="btn btn-sm btn-outline-secondary" type="button" title="Inline Formula"
                @click="$refs.editor?.make('formula-inline')">
                <i class="bi bi-currency-dollar"></i>
                <div v-if="showLabels">Inline Formula</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button" title="Formula Block"
                @click="$refs.editor?.make('formula')">
                <i class="bi bi-currency-dollar"></i>
                <i class="bi bi-currency-dollar icon-overlay"></i>
                <div v-if="showLabels">Formula Block</div>
              </button>
            </div>

            <div class="btn-group" role="group" aria-label="ASCII-art drawings">
              <button class="btn btn-sm btn-outline-secondary" type="button" title="Graph"
                @click="$refs.editor?.make('graph')">
                <i class="bi bi-graph-down"></i>
                <div v-if="showLabels">Graph</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button" title="ASCII-Art"
                @click="$refs.editor?.make('ascii')">
                <i class="bi bi-boxes"></i>
                <div v-if="showLabels">ASCII-Art</div>
              </button>
            </div>

            <div class="btn-group" role="group" aria-label="MathJS helpers">
              <button class="btn btn-sm btn-outline-secondary" type="button"
                title="MathJS - Evaluate Expression (Ctrl+E)" @click="$refs.editor?.make('mathjs-evaluate')">
                <i class="bi bi-gear"></i>
                <div v-if="showLabels">MathJS - Evaluate Expression (Ctrl+E)</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button"
                title="MathJS - Simplify Expression (Ctrl+M)" @click="$refs.editor?.make('mathjs-simplify')">
                <i class="bi bi-gear"></i>
                <i class="bi bi-lightning-charge icon-overlay"></i>
                <div v-if="showLabels">MathJS - Simplify Expression (Ctrl+M)</div>
              </button>

              <button class="btn btn-sm btn-outline-secondary" type="button" title="MathJS - Convert to TeX (Ctrl+O)"
                @click="$refs.editor?.make('mathjs-tex')">
                <i class="bi bi-gear"></i>
                <i class="bi icon-overlay">TeX</i>
                <div v-if="showLabels">MathJS - Convert to TeX (Ctrl+O)</div>
              </button>
            </div>
          </div>
        </div>

        <div class="tab-pane fade" id="file" role="filepanel" aria-labelledby="file-tab">
          <div class="container-fluid"
            style="display: flex; flex-direction: row; justify-content: space-between; align-items: center;">
            <a v-if="!embed" class="navbar-brand" href="./" data-link="true">
              <img src="../../assets/logo.png" alt="LiaScript" height="28" />
              <span id="lia-edit">LiaEdit</span>
            </a>
            <span v-else class="navbar-brand">
              <img src="../../assets/logo.png" alt="LiaScript" height="28" />
              <span id="lia-edit">LiaDemo</span>
            </span>

            <button type="button" class="btn btn-outline-secondary me-2 px-3" @click="switchLights()"
              title="Switch between light and dark mode">
              <i :class="lightMode"></i>
            </button>

            <div class="btn-toolbar btn-group-sm" role="toolbar" aria-label="Toolbar with button groups">
              <div class="btn-group btn-outline-secondary me-2" role="group"
                aria-label="Basic radio toggle button group">
                <input type="radio" class="btn-check" name="btnradio" id="btnradio1" autocomplete="off"
                  @click="changeMode(-1)" :checked="mode < 0" />
                <label class="btn btn-outline-secondary" for="btnradio1" title="Editor only">
                  <i class="bi bi-pencil"></i>
                </label>

                <input type="radio" class="btn-check" name="btnradio" id="btnradio2" autocomplete="off"
                  :checked="mode === 0" @click="changeMode(0)" />
                <label class="btn btn-outline-secondary" for="btnradio2" title="Split view">
                  <i class="bi bi-layout-split" style="display: inline-block"
                    :style="{ transform: horizontal ? 'rotate(90deg)' : 'rotate(0deg)' }"></i>
                </label>

                <input type="radio" class="btn-check" name="btnradio" id="btnradio3" autocomplete="off"
                  @click="changeMode(1)" :checked="mode > 0" />
                <label class="btn btn-outline-secondary" for="btnradio3" title="Preview only">
                  <i class="bi bi-eye"></i>
                </label>
              </div>
            </div>


            <div class="btn-toolbar btn-group-sm" role="toolbar" aria-label="Toolbar with button groups">

              <button type="button" class="btn btn-outline-secondary me-2 px-3" @click="syncViaHttp()"
                title="Publish document">
                <i class="bi bi-floppy"></i>
              </button>

              <button type="button" class="btn btn-outline-secondary me-2 px-3" :class="{ 'active': autoPublish }"
                @click="autoPublish = !autoPublish" title="Auto publish">
                <i class="bi bi-robot"></i>
              </button>

              <button type="button" class="btn btn-outline-secondary me-2 px-3" :class="{ 'active': autoCompile }"
                @click="autoCompile = !autoCompile" title="Auto compile">
                <i :class="autoCompile ? 'bi bi-check' : 'bi bi-x'"></i>
              </button>

              <button type="button" class="btn btn-outline-secondary me-2 px-3" @click="compile()"
                title="Compile (Ctrl+S)">
                <i class="bi bi-arrow-counterclockwise"></i>
              </button>
            </div>

            <!-- Drop-Down Navigation -->

            <button v-if="!embed" class="btn btn-outline-secondary me-2 px-3" type="button" data-bs-toggle="collapse"
              data-bs-target="#navbarSupportedContent" aria-controls="navbarSupportedContent" aria-expanded="false"
              aria-label="Toggle navigation">
              <span class="navbar-toggler-icon"></span>
            </button>

            <div v-if="!embed" class="collapse navbar-collapse" id="navbarSupportedContent">
              <!-- SPAN -->
              <div class="navbar-nav me-auto mb-lg-0"></div>

              <div class="navbar-nav mb-2 mb-lg-0">
                <div class="nav-item nav-item-sm ml-4 me-4">
                  <a class="nav-link" aria-current="page" href="./?/edit" title="Create a new and empty document"
                    data-link>
                    <i class="bi bi-plus"></i>
                    New
                  </a>
                </div>

                <div class="nav-item me-4">
                  <button type="button" class="btn nav-link btn-link" @click="fork"
                    title="Create a copy of this document">
                    <i class="bi bi-signpost-split"></i>
                    Fork
                  </button>
                </div>

                <div class="nav-item dropdown me-4">
                  <a class="nav-link dropdown-toggle" href="#" role="button" data-bs-toggle="dropdown"
                    aria-expanded="false">
                    Menu
                  </a>

                  <ul class="dropdown-menu">
                    <li>
                      <h6 class="dropdown-header fw-light">Share editor ...</h6>
                    </li>
                    <li>
                      <span class="d-inline-block" tabindex="0" data-toggle="tooltip"
                        title="Fork this document before you can use this function">
                        <button class="btn dropdown-item btn-link" @click="shareLink" :disabled="!storageId">
                          collaboration link
                        </button>
                      </span>
                    </li>
                    <li>
                      <button class="btn dropdown-item btn-link" @click="shareCode">
                        snapshot url
                      </button>
                    </li>
                    <li>
                      <button class="btn dropdown-item btn-link" @click="embedCode">
                        embed code
                      </button>
                    </li>
                    <li>
                      <button class="btn dropdown-item btn-link" @click="shareFile">
                        external resource
                      </button>
                    </li>
                    <li>
                      <hr class="dropdown-divider" />
                    </li>
                    <li>
                      <h6 class="dropdown-header fw-light">Share course via ...</h6>
                    </li>
                    <li>
                      <span class="d-inline-block" tabindex="0" data-toggle="tooltip"
                        title="You have to export this file to GitHub gist before you can use this functionality">
                        <a class="dropdown-item" :class="{ disabled: !meta.meta?.gist_url }"
                          :href="LiaScriptURL + '?' + meta.meta?.gist_url" target="_blank">
                          GitHub gist link
                        </a>
                      </span>
                    </li>
                    <li>
                      <button class="btn dropdown-item btn-link" @click="shareData">
                        data-URI
                      </button>
                    </li>
                    <li>
                      <div class="d-inline-block" tabindex="0" style="width: 100%" data-toggle="tooltip"
                        title="This function is only available if you have shared an external resource">
                        <a class="btn dropdown-item btn-link" :class="{ disabled: !fileUrl }"
                          :href="LiaScriptURL + '?' + fileUrl" target="_blank" title="open this course on LiaScript">
                          file URL
                        </a>
                      </div>
                    </li>
                    <li>
                      <hr class="dropdown-divider" />
                    </li>
                    <li>
                      <h6 class="dropdown-header fw-light">Download to ...</h6>
                    </li>
                    <li>
                      <button class="btn dropdown-item btn-link" @click="download">
                        README.md
                      </button>
                    </li>
                    <li>
                      <button class="btn dropdown-item btn-link" @click="downloadZip">
                        Project-{{ $props?.storageId?.slice(0, 8) || "xxxxxxxx" }}.zip
                      </button>
                    </li>
                    <!--li>
                <hr class="dropdown-divider">
              </li>
              <li>
                <h6 class="dropdown-header fw-light">
                  Upload from ...
                </h6>
              </li>

              <li>
                <input
                  type="file"
                  id="uploadMarkdown"
                  style="display: none;"
                >
                <button
                  class="btn dropdown-item btn-link"
                  @click="upload"
                >
                  README.md
                </button>
              </li>
              <li>
                <input
                  type="file"
                  id="uploadZip"
                  style="display: none;"
                >
                <button
                  class="btn dropdown-item btn-link"
                  @click="uploadZip"
                >
                  Project.zip
                </button>
              </li-->
                    <li>
                      <hr class="dropdown-divider" />
                    </li>
                    <li>
                      <h6 class="dropdown-header fw-light">Export to...</h6>
                    </li>
                    <li>
                      <span class="d-inline-block" style="width: 100%" tabindex="0" data-toggle="tooltip"
                        title="Fork this document before you can use this function">
                        <a class="btn dropdown-item btn-link" :class="{ disabled: !storageId }" aria-current="page"
                          target="_blank" :href="urlPath(['export', 'github', storageId])"
                          title="Store the document on github">
                          GitHub gist
                        </a>
                      </span>
                    </li>
                  </ul>
                </div>

                <div class="nav-item dropdown me-4">
                  <button class="btn badge dropdown-toggle p-3"
                    :class="conn.users === 0 ? 'bg-secondary' : 'bg-primary'" data-bs-toggle="dropdown"
                    aria-expanded="false" style="width: 100%">
                    {{ conn.type }}
                    <i class="bi bi-people-fill mx-1"></i>
                    <span class="mx-1">
                      {{ conn.users > 0 ? conn.users : "" }}
                    </span>
                  </button>

                  <ul class="dropdown-menu">
                    <li>
                      <span class="d-inline-block" style="width: 100%" tabindex="0" data-toggle="tooltip"
                        title="Fork this document before you can use this function">
                        <a class="btn dropdown-item btn-link" :class="{ disabled: !storageId }" aria-current="page"
                          :href="this.urlPath(['edit', storageId])" title="Store the document on github">
                          Offline
                        </a>
                      </span>
                    </li>

                    <li>
                      <span class="d-inline-block" style="width: 100%" tabindex="0" data-toggle="tooltip"
                        title="Fork this document before you can use this function">
                        <a class="btn dropdown-item btn-link" :class="{ disabled: !storageId }" aria-current="page"
                          :href="this.urlPath(['edit', storageId, 'webrtc'])" title="Store the document on github">
                          WebRTC
                        </a>
                      </span>
                    </li>
                    <li>
                      <span class="d-inline-block" style="width: 100%" tabindex="0" data-toggle="tooltip"
                        title="Fork this document before you can use this function">
                        <a class="btn dropdown-item btn-link" :class="{ disabled: !storageId }" aria-current="page"
                          :href="this.urlPath(['edit', storageId, 'websocket'])" title="Store the document on github">
                          Websocket
                        </a>
                      </span>
                    </li>
                  </ul>
                </div>
              </div>
            </div>
          </div>

        </div>

      </div>

    </div>
  </nav>

  <div class="container p-0" style="max-width: 100%">
    <splitpanes id="liascript-ide" class="default-theme" style="height: calc(100vh - 56px)" @resize="resizing = true"
      @resized="resizing = false" :horizontal="horizontal">
      <pane :hidden="mode > 0" style="border-right: solid lightgray 2px" :class="{
        fullHeight: mode < 0 && horizontal,
        fullWidth: mode < 0 && !horizontal,
      }">
        <Editor class="col w-100 p-0 h-100" @compile="compile" @ready="editorReady" @online="online" @goto="gotoPreview"
          :storage-id="$props.storageId" :content="$props.content" ref="editor" :connection="$props.connection"
          :toolbar="false">
        </Editor>
      </pane>

      <pane :hidden="mode < 0" :class="{
        fullHeight: mode > 0 && horizontal,
        fullWidth: mode > 0 && !horizontal,
      }">
        <div v-show="previewNotReady" style="position: absolute; background-color: white; width: 50%; height: 100%">
          <div class="spinner-grow" style="
              width: 5rem;
              height: 5rem;
              margin-top: 50%;
              margin-left: 45%;
              margin-right: 45%;
            " role="status">
            <span class="visually-hidden">Loading...</span>
          </div>
        </div>

        <div v-show="resizing" style="position: absolute; width: 100%; height: 100%"></div>

        <Preview @ready="previewReady" @update="previewUpdate" @goto="gotoEditor" :fetchError="fetchError"
          :class="{ invisible: previewNotReady }" />
      </pane>
    </splitpanes>
  </div>

  <Modal ref="modal" />
</template>

<style scoped>
#liascript {
  height: 100vh;
}

.invisible {
  visibility: hidden;
}

.fullWidth {
  min-width: 100%;
}

.fullHeight {
  min-height: calc(100% - 10px);
}

@media (max-width: 460px) {
  .btn {
    padding: 0.2rem 0.4rem;
  }
}

#lia-edit {
  margin-left: 10px;
}

@media (max-width: 418px) {
  #lia-edit {
    display: none;
  }

  .btn {
    padding: 0.2rem 0.4rem;
  }
}

.tab-content {
  background-color: white;
}
</style>

<style>
.splitpanes__splitter {
  background-color: #f8f9fa !important;
}

.splitpanes--vertical>.splitpanes__splitter {
  min-width: 10px;
}

.splitpanes--horizontal>.splitpanes__splitter {
  min-height: 10px;
}
</style>
