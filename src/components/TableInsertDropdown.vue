<script lang="ts">
export default {
  name: 'TableInsertDropdown',
  props: {
    showLabels: {
      type: Boolean,
      default: false
    }
  },
  data() {
    return {
      hoveredRows: 0,
      hoveredCols: 0,
      dropdownOpen: false
    }
  },
  methods: {
    updateSelection(row, col) {
      this.hoveredRows = row
      this.hoveredCols = col
    },
    resetSelection() {
      this.hoveredRows = 0
      this.hoveredCols = 0
    },
    isSelected(row, col) {
      return row <= this.hoveredRows && col <= this.hoveredCols
    },
    insertTable() {
      this.$emit('insert-table', { cols: this.hoveredCols, rows: this.hoveredRows })
      this.dropdownOpen = false
    },
    toggleDropdown() {
      this.dropdownOpen = !this.dropdownOpen
    }
  }
}
</script>

<style scoped>
.table-selector {
  user-select: none;
}

.table-grid-container {
  position: relative;
}

.table-cell {
  width: 24px;
  height: 24px;
  padding: 0;
  transition: all 0.15s ease;
}

.table-cell.active {
  background-color: var(--bs-primary) !important;
  border-color: var(--bs-primary) !important;
}

.gap-1 {
  gap: 0.25rem !important;
}

.btn-group {
  align-items: flex-start;
}

.btn-group>.d-flex {
  padding: 0 1px;
}

small {
  font-size: 0.7rem;
  margin-top: 2px;
}
</style>

<template>
  <div class="dropdown">
    <div class="btn-group me-2" role="group" aria-label="Table">
      <button type="button" class="btn btn-sm btn-outline-secondary" @click="insertTable" title="Table">
        <i class="bi bi-table"></i>
        <div v-if="showLabels">Table</div>
      </button>
      <button type="button" class="btn btn-sm btn-outline-secondary dropdown-toggle dropdown-toggle-split"
        @click="toggleDropdown" title="Table options">
        <span class="visually-hidden">Toggle Dropdown</span>
      </button>
      <div class="dropdown-menu p-2" :class="{ 'show': dropdownOpen }" style="position: absolute;"
        @mouseleave="dropdownOpen = false">
        <div class="table-selector">
          <small class="text-muted mb-2 d-block">Drag to select table dimensions</small>
          <div class="table-grid-container" @mouseleave="resetSelection">
            <div class="table-grid">
              <div v-for="row in 8" :key="'r' + row" class="d-flex gap-1">
                <div v-for="col in 10" :key="'c' + col" class="table-cell btn btn-light border"
                  :class="{ 'active': isSelected(row, col) }" @mouseover="updateSelection(row, col)"
                  @click="insertTable"></div>
              </div>
            </div>
            <div class="size-label mt-2 text-muted small" v-if="hoveredRows && hoveredCols">
              <span class="badge bg-secondary">{{ hoveredCols }} × {{ hoveredRows }} Table</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
