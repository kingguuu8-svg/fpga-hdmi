#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <drm.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

static int
get_capability(int fd, uint64_t capability, uint64_t *value)
{
  *value = 0u;
  if (drmGetCap(fd, capability, value) != 0) {
    return -errno;
  }
  return 0;
}

int
main(int argc, char **argv)
{
  const char *device = argc > 1 ? argv[1] : "/dev/dri/card0";
  drmVersionPtr version;
  drmModeResPtr resources;
  int fd;
  int i;
  int connected = 0;
  int has_720p = 0;
  uint64_t dumb = 0u;
  uint64_t prime = 0u;
  uint64_t async_flip = 0u;

  fd = open(device, O_RDWR | O_CLOEXEC);
  if (fd < 0) {
    fprintf(stderr, "DRM_PRIME_PROBE_FAIL stage=open device=%s errno=%d error=%s\n",
            device, errno, strerror(errno));
    return 1;
  }

  version = drmGetVersion(fd);
  if (version != NULL) {
    printf("DRM_DRIVER name=%s date=%s desc=%s\n",
           version->name != NULL ? version->name : "unknown",
           version->date != NULL ? version->date : "unknown",
           version->desc != NULL ? version->desc : "unknown");
    drmFreeVersion(version);
  }

  if (get_capability(fd, DRM_CAP_DUMB_BUFFER, &dumb) != 0 ||
      get_capability(fd, DRM_CAP_PRIME, &prime) != 0 ||
      get_capability(fd, DRM_CAP_ASYNC_PAGE_FLIP, &async_flip) != 0) {
    fprintf(stderr, "DRM_PRIME_PROBE_FAIL stage=getcap error=%s\n",
            strerror(errno));
    close(fd);
    return 1;
  }

  printf("DRM_CAP dumb=0x%llx prime=0x%llx prime_export=%u prime_import=%u async_page_flip=%u\n",
         (unsigned long long)dumb, (unsigned long long)prime,
         (prime & DRM_PRIME_CAP_EXPORT) != 0u,
         (prime & DRM_PRIME_CAP_IMPORT) != 0u,
         async_flip != 0u);

  resources = drmModeGetResources(fd);
  if (resources == NULL) {
    fprintf(stderr, "DRM_PRIME_PROBE_FAIL stage=get-resources errno=%d error=%s\n",
            errno, strerror(errno));
    close(fd);
    return 1;
  }

  for (i = 0; i < resources->count_connectors; i++) {
    drmModeConnectorPtr connector;
    int mode_index;

    connector = drmModeGetConnector(fd, resources->connectors[i]);
    if (connector == NULL) {
      continue;
    }
    if (connector->connection == DRM_MODE_CONNECTED) {
      connected++;
      printf("DRM_CONNECTOR id=%u connection=connected modes=%d\n",
             connector->connector_id, connector->count_modes);
      for (mode_index = 0; mode_index < connector->count_modes; mode_index++) {
        drmModeModeInfoPtr mode = &connector->modes[mode_index];
        printf("DRM_MODE connector=%u name=%s width=%u height=%u clock=%u\n",
               connector->connector_id, mode->name, mode->hdisplay,
               mode->vdisplay, mode->clock);
        if (mode->hdisplay == 1280u && mode->vdisplay == 720u) {
          has_720p = 1;
        }
      }
    }
    drmModeFreeConnector(connector);
  }
  drmModeFreeResources(resources);
  close(fd);

  if (dumb == 0u || (prime & DRM_PRIME_CAP_EXPORT) == 0u ||
      (prime & DRM_PRIME_CAP_IMPORT) == 0u || connected == 0 ||
      has_720p == 0) {
    printf("DRM_PRIME_PROBE_FAIL stage=capability-gate connected=%d has_720p=%d\n",
           connected, has_720p);
    return 2;
  }

  printf("DRM_PRIME_PROBE_OK device=%s connected=%d has_720p=%d\n",
         device, connected, has_720p);
  return 0;
}
