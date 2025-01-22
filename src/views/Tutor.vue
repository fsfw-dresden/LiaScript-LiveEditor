<script lang="ts">
import LiaScript from "./LiaScript.vue";
import Toast from "../components/Toast.vue";
import { LiaScriptURL, LiveEditorURL, StorageServerURL } from "../ts/utils";

function errorMsg(url: string, response: string) {
  return `# Ups, something went wrong
  
The following resource with the URL:

${url}

could not be loaded.

It responded with the following error message:

\`${response}\`

**Reasons:**

* The URL is wrong or the resource is not available anymore.
* Or, you are offline...`;
}

export default {
  name: "LiaScript-FileView",
  props: ["fileUrl"],
  data() {

    return {
      data: undefined,
      LiaScriptURL,
      LiveEditorURL,
    };
  },

  async created() {
    const response = await fetch(StorageServerURL + '/static/' + this.fileUrl);


    if (response.ok) {
      this.data = await response.text();
      const baseURL = this.fileUrl.replace(/\/[^\/]*$/, "/");
      //this.data = replaceURLs(baseURL, this.data);
      //this.data = replaceMacroURLs("script", baseURL, this.data);
      //this.data = replaceMacroURLs("link", baseURL, this.data);
    } else {
      this.data = errorMsg(this.fileUrl, response.status + ": " + response.statusText);
    }
  },
  components: { LiaScript, Toast },
};
</script>

<template>
  <LiaScript v-if="data" :initial-content="data" :file-url="fileUrl" :storage-id="fileUrl" :enable-sync="true" >
  </LiaScript>
</template>
