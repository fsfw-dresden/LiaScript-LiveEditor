<script lang="ts">
import { StorageServerURL } from '../ts/utils';

const INIT_CODE = `
var blob = {};
var StorageServerURL = "${StorageServerURL}";
window.hasBlob = {};

var style = document.createElement('style');
style.innerHTML = \`
  .lia-header {
    border: none !important;
    background: none !important;
  }
  .lia-header__middle {
    display: none !important;
  }
  .lia-slide__container {
    margin-top: 0px !important;
  }
  .lia-toc--closed #lia-btn-toc {
    transform: translate(50vw, -50%) !important;
  }
\`;
document.head.insertBefore(style, document.head.firstChild);


const fixImageUrls = function() {

  const origin = window.location.origin;
  const parentUrl = window.parent.location.href;
  const documentId = parentUrl.split('?/tutor/')[1];
  const documentPath = documentId.split('/').slice(0, -1).join('/');

  function checkUrlNeedsReplacement(url) {
    return url && !url.startsWith('blob:') && ((StorageServerURL && StorageServerURL !== origin) ? url.includes(origin) : !url.includes('/static/')) && !url.startsWith(origin + '/liascript/');
  }
  
  const images = document.querySelectorAll('img,picture');
  for (let i = 0; i < images.length; i++) {
    let image = images[i];
    if (checkUrlNeedsReplacement(image.src)) {
      image.src = image.src.replace(origin, StorageServerURL + '/static/' + documentPath);
    }
  }

  const mediaSelector = ['video', 'audio'];
  const mediaTags = document.querySelectorAll(mediaSelector.join(','));
  for (let i = 0; i < mediaTags.length; i++) {
    let media = mediaTags[i];
    const sources = media.querySelectorAll('source');
    for (let j = 0; j < sources.length; j++) {
      let source = sources[j];
      if (checkUrlNeedsReplacement(source.src)) {
        source.src = source.src.replace(origin, StorageServerURL + '/static/' + documentPath);
      }
    }
  }
}


// Run URL fix whenever DOM changes
const observer = new MutationObserver(fixImageUrls);
observer.observe(document.body, {
  childList: true,
  subtree: true
});

window.injectHandler = function (param) {
  let url

  console.log("param", param);

  if (blob[param.src]) {
    url = blob[param.src]
  }
  else if (param.data) {
    url = URL.createObjectURL(param.data)
    blob[param.src] = url
  } else {
    return
  }

  const src = window.location.origin + param.src

  switch (param.tag) {
    case "img": {
      const images = document.querySelectorAll('img,picture')
      for (let i = 0; i < images.length; i++) {
        let image = images[i]
        if (image.src == src || image.src.endsWith(param.src)) {
          console.log("image.src includes", image.src);
          image.src = url

          if (image.onclick) {
            image.onclick = function () {
              window.LIA.img.click(url)
            }
          }
        }
      }

      break
    }

    case "audio": {
      const nodes = document.querySelectorAll('source')

      for (let i = 0; i < nodes.length; i++) {
        let elem = nodes[i]
        if (elem.src == src) {
          const parent = elem.parentNode
          if (!parent.paused) {
            parent.pause()
          }

          elem.src = url
          elem.removeAttribute("onerror")

          // this forces the player to reload
          parent.innerHTML = elem.outerHTML
          parent.play()
        }
      }

      break
    }

    case "video": {
      let nodes = document.querySelectorAll('source')

      for (let i = 0; i < nodes.length; i++) {
        let elem = nodes[i]
        if (elem.src == src) {
          const parent = elem.parentNode
          parent.src = url
          elem.src = url
          parent.load()
          parent.onloadeddata = function() {
            parent.play()
          }
        }
      }

      nodes = document.querySelectorAll('video')

      for (let i = 0; i < nodes.length; i++) {
        let elem = nodes[i]

        if (elem.src == src) {
          elem.src = url
          elem.load()
          elem.onloadeddata = function() {
            elem.play()
          }
        }
      }

      break
    }

    case "script": {
      const tag = document.createElement('script')
      tag.src = url
      document.head.appendChild(tag)

      break
    }

    case "link": {
      const tag = document.createElement('link')
      tag.href = url
      tag.rel = 'stylesheet'
      document.head.appendChild(tag)

      break
    }

    default: {
      console.warn("could not handle tag =>", param)
    }
  }
}


window.LIA.fetchError = (tag, src) => {
  if (src.startsWith("http") || src.startsWith("https")) {
    fetch(src)
      .then(response => response.blob())
      .then(blob => {
        window.injectHandler({tag, src, data: blob})
      })
      .catch(error => {
        console.error("could not fetch", src, error)
        parent.postMessage({cmd: 'media.load', param: {tag, src}}, "*")
      })
  }

  if (blob[src]) {
    window.injectHandler({tag, src})
  } else {
    parent.postMessage({cmd: 'media.load', param: {tag, src}}, "*")
  }
}
`;

export default {
  name: "Preview",

  emits: ["ready", "update", "goto"],

  props: { fetchError: Function },

  data() {
    window.addEventListener(
      "message",
      (event) => {
        switch (event.data.cmd) {
          case "media.load": {
            const param = event.data.param;

            if (this.fetchError) {
              const blob = this.fetchError(param.src);
              //(param.tag, param.src);
              if (blob) {
                this.sendToLia("inject", {
                  tag: param.tag,
                  src: param.src,
                  data: new Blob(
                    [blob],
                    param.src.toLowerCase().endsWith(".svg")
                      ? { type: "image/svg+xml" }
                      : {}
                  ),
                });
              }
            }
            break;
          }
        }
      },
      false
    );

    return {
      isReady: false,
      // @ts-ignore
      responsiveVoiceKey: process.env.RESPONSIVEVOICE_KEY,
      sendToLia: null,
    };
  },

  methods: {
    onReady(params: any) {
      const iframe = document.getElementById("liascript-preview") as HTMLIFrameElement;

      if (!this.isReady && iframe && iframe.contentWindow) {
        this.isReady = true;

        // only inject if key has been defined
        if (this.responsiveVoiceKey) {
          iframe.contentWindow["LIA"].injectResposivevoice(this.responsiveVoiceKey);
        }

        // @ts-ignore
        this.$emit("ready", iframe.contentWindow["LIA"]);

        const self = this;
        iframe.contentWindow["LIA"].lineGoto = function (line: number) {
          self.$emit("goto", line);
        };

        this.sendToLia = function (cmd: string, param: any) {
          iframe.contentWindow?.postMessage({ cmd, param }, "*");
        };

        this.sendToLia("eval", INIT_CODE);
      }

      if (params) {
        this.$emit("update", params);
      }
    },
  },

  mounted() {
    const iframe = document.getElementById("liascript-preview");

    // @ts-ignore
    if (iframe && iframe.contentWindow) {
      // @ts-ignore
      if (!iframe.contentWindow["LIA"]) {
        // @ts-ignore
        iframe.contentWindow["LIA"] = {};
      }

      // @ts-ignore
      iframe.contentWindow["LIA"].onReady = this.onReady;
    }
  },
};
</script>

<template>
  <iframe id="liascript-preview" src="./liascript/index.html?" allow="autoplay"></iframe>
</template>

<style scoped>
#liascript-preview {
  height: 100%;
  width: 100%;
}
</style>
