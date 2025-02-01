// package: markdown
// file: app/domain/markdown.proto

import * as jspb from "google-protobuf";

export class MarkdownMessage extends jspb.Message {
  getType(): string;
  setType(value: string): void;

  getFilename(): string;
  setFilename(value: string): void;

  getContent(): string;
  setContent(value: string): void;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): MarkdownMessage.AsObject;
  static toObject(includeInstance: boolean, msg: MarkdownMessage): MarkdownMessage.AsObject;
  static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
  static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
  static serializeBinaryToWriter(message: MarkdownMessage, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): MarkdownMessage;
  static deserializeBinaryFromReader(message: MarkdownMessage, reader: jspb.BinaryReader): MarkdownMessage;
}

export namespace MarkdownMessage {
  export type AsObject = {
    type: string,
    filename: string,
    content: string,
  }
}

