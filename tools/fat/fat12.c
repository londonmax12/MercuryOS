#ifdef __GNUC__
#define PACKED_STRUCT __attribute__((packed))
#else
#define PACKED_STRUCT
#endif

typedef uint8_t bool;
#define true 1
#define false 0

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

typedef struct 
{
    uint8_t BootJumpInstruction[3];
    uint8_t OemIdentifier[8];
    uint16_t BytesPerSector;
    uint8_t SectorsPerCluster;
    uint16_t ReservedSectors;
    uint8_t FatCount;
    uint16_t DirEntryCount;
    uint16_t TotalSectors;
    uint8_t MediaDescriptorType;
    uint16_t SectorsPerFat;
    uint16_t SectorsPerTrack;
    uint16_t Heads;
    uint32_t HiddenSectors;
    uint32_t LargeSectorCount;

    uint8_t DriveNumber;
    uint8_t _Reserved;
    uint8_t Signature;
    uint32_t VolumeId;
    uint8_t VolumeLabel[11];
    uint8_t SystemId[8];
} PACKED_STRUCT BootSector;

typedef struct 
{
    uint8_t Name[11];
    uint8_t Attributes;
    uint8_t _Reserved;
    uint8_t CreatedTimeTenths;
    uint16_t CreatedTime;
    uint16_t CreatedDate;
    uint16_t AccessedDate;
    uint16_t FirstClusterHigh;
    uint16_t ModifiedTime;
    uint16_t ModifiedDate;
    uint16_t FirstClusterLow;
    uint32_t Size;
} PACKED_STRUCT DirectoryEntry;

typedef struct 
{
    BootSector BootSector;
    uint8_t* FAT;
    DirectoryEntry* RootDirectory;
    uint32_t RootDirectoryEnd;
} FAT12;

bool ReadSectors(FAT12* fs, FILE* disk, uint32_t lba, uint32_t count, void* bufferOut)
{
    bool ok = true;
    ok = ok && (fseek(disk, lba * fs->BootSector.BytesPerSector, SEEK_SET) == 0);
    ok = ok && (fread(bufferOut, fs->BootSector.BytesPerSector, count, disk) == count);
    return ok;
}

DirectoryEntry* FindFile(FAT12* fs, const char* name)
{
    for (uint32_t i = 0; i < fs->BootSector.DirEntryCount; i++)
    {
        if (memcmp(name, fs->RootDirectory[i].Name, 11) == 0)
            return &fs->RootDirectory[i];
    }

    return NULL;
}

bool ReadFile(FAT12* fs, DirectoryEntry* fileEntry, FILE* disk, uint8_t* outputBuffer)
{
    bool ok = true;
    uint16_t currentCluster = fileEntry->FirstClusterLow;

    do {
        uint32_t lba = fs->RootDirectoryEnd + (currentCluster - 2) * fs->BootSector.SectorsPerCluster;
        ok = ok && ReadSectors(fs, disk, lba, fs->BootSector.SectorsPerCluster, outputBuffer);
        outputBuffer += fs->BootSector.SectorsPerCluster * fs->BootSector.BytesPerSector;

        uint32_t fatIndex = currentCluster * 3 / 2;
        if (currentCluster % 2 == 0)
            currentCluster = (*(uint16_t*)(fs->FAT + fatIndex)) & 0x0FFF;
        else
            currentCluster = (*(uint16_t*)(fs->FAT + fatIndex)) >> 4;

    } while (ok && currentCluster < 0x0FF8);

    return ok;
}

int main(int argc, char** argv)
{
    if (argc < 3) {
        printf("Syntax: %s <disk image> <file name>\n", argv[0]);
        return -1;
    }

    FILE* disk = fopen(argv[1], "rb");
    if (!disk) {
        fprintf(stderr, "Failed to open disk image: %s!\n", argv[1]);
        return -1;
    }

    FAT12 fs;
    fs.FAT = 0;
    fs.RootDirectory = 0;

    if (!fread(&fs.BootSector, sizeof(fs.BootSector), 1, disk) > 0) {
        fprintf(stderr, "Failed to read boot sector\n");
        return -2;
    }

    fs.FAT = (uint8_t*)malloc(fs.BootSector.SectorsPerFat * fs.BootSector.BytesPerSector);
    if (!ReadSectors(&fs, disk, fs.BootSector.ReservedSectors, fs.BootSector.SectorsPerFat, fs.FAT)) {
        fprintf(stderr, "Failed to read FAT\n");
        free(fs.FAT);
        return -3;
    }

    uint32_t lba = fs.BootSector.ReservedSectors + fs.BootSector.SectorsPerFat * fs.BootSector.FatCount;
    uint32_t size = sizeof(DirectoryEntry) * fs.BootSector.DirEntryCount;
    uint32_t sectors = (size / fs.BootSector.BytesPerSector);
    if (size % fs.BootSector.BytesPerSector > 0)
        sectors++;

    fs.RootDirectoryEnd = lba + sectors;
    fs.RootDirectory = (DirectoryEntry*)malloc(sectors * fs.BootSector.BytesPerSector);

    if (!ReadSectors(&fs, disk, lba, sectors, fs.RootDirectory)) {
        fprintf(stderr, "Failed to read root directory sectors\n");
        free(fs.FAT);
        free(fs.RootDirectory);
        return -4;
    }

    DirectoryEntry* fileEntry = FindFile(&fs, argv[2]);
    if (!fileEntry) {
        fprintf(stderr, "Failed to find file %s!\n", argv[2]);
        free(fs.FAT);
        free(fs.RootDirectory);
        return -5;
    }

    uint8_t* buffer = (uint8_t*)malloc(fileEntry->Size + fs.BootSector.BytesPerSector);
    if (!ReadFile(&fs, fileEntry, disk, buffer)) {
        fprintf(stderr, "Failed to read file %s!\n", argv[2]);
        free(fs.FAT);
        free(fs.RootDirectory);
        free(buffer);
        return -5;
    }

    for (size_t i = 0; i < fileEntry->Size; i++)
    {
        if (isprint(buffer[i])) {
            fputc(buffer[i], stdout);
            continue;
        }
   
        printf("<%02x>", buffer[i]);
    }
    printf("\n");

    free(buffer);
    free(fs.FAT);
    free(fs.RootDirectory);
    return 0;
}
