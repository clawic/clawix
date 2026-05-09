// Icon barrel.
//
// Strategy mirrors the Mac (LucideBridge.swift):
//   - 22 custom hand-crafted glyphs ported from Sources/Clawix/*Icon.swift
//     live under ./custom and are re-exported with their canonical names.
//   - The other 76 glyphs the Mac uses are part of the public Lucide set,
//     so we serve them straight from `lucide-react`. Same SVG paths as the
//     Mac runtime, so those stay pixel-perfect.
//   - SF Symbol references in older Mac code map to Lucide equivalents
//     via the dispatcher at the bottom (`autoIcon`), matching
//     LucideBridge.swift:299-320.
import type { LucideProps } from "lucide-react";
import {
  // 76 icons mirroring the Mac LucideIcons/ folder.
  AppWindow, ArrowDown, ArrowDownToLine, ArrowLeft, ArrowRight,
  ArrowRightToLine, ArrowUpRight, AudioWaveform, BadgeCheck, Braces,
  Camera, ChevronDown, ChevronLeft, ChevronRight, ChevronUp,
  CircleAlert, CircleCheck, CircleDot, CircleStop, CircleX,
  Clock, Database, Download, Drama, Ellipsis,
  Eye, EyeOff, FileQuestion, FileText, Folder,
  Glasses, IdCard, Image, ImageOff, Images,
  Inbox, Info, Laptop, Link,
  ListChecks, List, Lock, Maximize2, MessageCircle,
  Minimize2, Minus, Moon, Paperclip, Pause,
  Play, Plus, RefreshCw, RotateCcw, RotateCw,
  Scan, Send, Share2, ShieldAlert, SquareArrowOutUpRight,
  SquareDashed, Square, Star, AlignLeft, Tornado,
  Trash, TriangleAlert, Undo2, Webhook, Workflow,
  X, Zap, ZapOff,
  // Convenience aliases referenced from older code.
  MessageSquare, Sidebar, Settings, Pin, Archive, Mic,
  FolderOpen, Terminal, Search, Globe, Bot,
  KeyRound, Brain, Puzzle, Server, Construction,
} from "lucide-react";

// Custom hand-crafted glyphs.
export { ArrowUpIcon } from "./custom/arrow-up";
export { BotIcon } from "./custom/bot";
export { CheckIcon } from "./custom/check";
export { ClawixLogoIcon } from "./custom/clawix-logo";
export { CornerBracketsIcon } from "./custom/corner-brackets";
export { CursorIcon } from "./custom/cursor";
export { ExternalLinkIcon } from "./custom/external-link";
export { FileChipIcon } from "./custom/file-chip";
export { FolderOpenIcon } from "./custom/folder-open";
export { FolderStackIcon } from "./custom/folder-stack";
export { GlobeIcon } from "./custom/globe";
export { LocalModelsIcon } from "./custom/local-models";
export { McpIcon } from "./custom/mcp";
export { MicIcon } from "./custom/mic";
export { OpenInAppIcon } from "./custom/open-in-app";
export { SearchIcon } from "./custom/search";
export { SettingsIcon } from "./custom/settings";
export { SignOutIcon } from "./custom/sign-out";
export { StopSquircle } from "./custom/stop-squircle";
export { TerminalIcon } from "./custom/terminal";
export { UsageIcon } from "./custom/usage";
export { WordWrapIcon } from "./custom/word-wrap";
export { WrenchIcon } from "./custom/wrench";

// Lucide wrappers. strokeWidth 1.5 matches the Mac LucideIcon defaults.
const defaults = (size?: number, sw?: number): LucideProps => ({
  size: size ?? 16,
  strokeWidth: sw ?? 1.5,
  absoluteStrokeWidth: false,
});
type IconArgs = { size?: number; className?: string; strokeWidth?: number };
const wrap = (Comp: typeof MessageSquare) =>
  ({ size, className, strokeWidth }: IconArgs) =>
    <Comp {...defaults(size, strokeWidth)} className={className} />;

// 8 routes used by the sidebar route switcher (canonical aliases).
export const ChatIcon         = wrap(MessageSquare);
export const SidebarIcon      = wrap(Sidebar);
export const PinIcon          = wrap(Pin);
export const ArchiveIcon      = wrap(Archive);
export const SendIcon         = wrap(Send);
export const StopIcon         = wrap(Square);
export const PlusIcon         = wrap(Plus);
export const KeyIcon          = wrap(KeyRound);
export const DatabaseIcon     = wrap(Database);
export const BrainIcon        = wrap(Brain);
export const PuzzleIcon       = wrap(Puzzle);
export const ServerIcon       = wrap(Server);
export const ChevronLeftIcon  = wrap(ChevronLeft);
export const ChevronRightIcon = wrap(ChevronRight);
export const ChevronDownIcon  = wrap(ChevronDown);
export const ChevronUpIcon    = wrap(ChevronUp);
export const TriangleAlertIcon = wrap(TriangleAlert);
export const ShieldAlertIcon  = wrap(ShieldAlert);
export const CircleAlertIcon  = wrap(CircleAlert);
export const CircleCheckIcon  = wrap(CircleCheck);
export const CircleXIcon      = wrap(CircleX);
export const CircleDotIcon    = wrap(CircleDot);
export const CircleStopIcon   = wrap(CircleStop);
export const InfoIcon         = wrap(Info);
export const ConstructionIcon = wrap(Construction);

// Full Lucide bridge: any of the 76 icons the Mac uses are reachable through
// these named exports. Keep names sorted alphabetically and matching the Mac
// LucideIcons/<Name>Icon.swift filename.
export const AppWindowIcon          = wrap(AppWindow);
export const ArrowDownIcon          = wrap(ArrowDown);
export const ArrowDownToLineIcon    = wrap(ArrowDownToLine);
export const ArrowLeftIcon          = wrap(ArrowLeft);
export const ArrowRightIcon         = wrap(ArrowRight);
export const ArrowRightToLineIcon   = wrap(ArrowRightToLine);
export const ArrowUpRightIcon       = wrap(ArrowUpRight);
export const AudioWaveformIcon      = wrap(AudioWaveform);
export const BadgeCheckIcon         = wrap(BadgeCheck);
export const BracesIcon             = wrap(Braces);
export const CameraIcon             = wrap(Camera);
export const ClockIcon              = wrap(Clock);
export const DownloadIcon           = wrap(Download);
export const DramaIcon              = wrap(Drama);
export const EllipsisIcon           = wrap(Ellipsis);
export const EyeIcon                = wrap(Eye);
export const EyeOffIcon             = wrap(EyeOff);
export const FileQuestionMarkIcon   = wrap(FileQuestion);
export const FileTextIcon           = wrap(FileText);
export const FolderIcon             = wrap(Folder);
export const FolderClosedIcon       = wrap(Folder);
export const GlassesIcon            = wrap(Glasses);
export const IdCardIcon             = wrap(IdCard);
export const ImageIcon              = wrap(Image);
export const ImageOffIcon           = wrap(ImageOff);
export const ImagesIcon             = wrap(Images);
export const InboxIcon              = wrap(Inbox);
export const LaptopIcon             = wrap(Laptop);
export const LinkIcon               = wrap(Link);
export const ListChecksIcon         = wrap(ListChecks);
export const ListIcon               = wrap(List);
export const LockIcon               = wrap(Lock);
export const Maximize2Icon          = wrap(Maximize2);
export const MessageCircleIcon      = wrap(MessageCircle);
export const Minimize2Icon          = wrap(Minimize2);
export const MinusIcon              = wrap(Minus);
export const MoonIcon               = wrap(Moon);
export const PaperclipIcon          = wrap(Paperclip);
export const PauseIcon              = wrap(Pause);
export const PlayIcon               = wrap(Play);
export const RefreshCwIcon          = wrap(RefreshCw);
export const RotateCcwIcon          = wrap(RotateCcw);
export const RotateCwIcon           = wrap(RotateCw);
export const ScanIcon               = wrap(Scan);
export const Share2Icon             = wrap(Share2);
export const SquareArrowOutUpRightIcon = wrap(SquareArrowOutUpRight);
export const SquareDashedIcon       = wrap(SquareDashed);
export const SquareIcon             = wrap(Square);
export const StarIcon               = wrap(Star);
export const TextAlignStartIcon     = wrap(AlignLeft);
export const TornadoIcon            = wrap(Tornado);
export const TrashIcon              = wrap(Trash);
export const Undo2Icon              = wrap(Undo2);
export const WebhookIcon            = wrap(Webhook);
export const WorkflowIcon           = wrap(Workflow);
export const XIcon                  = wrap(X);
export const ZapIcon                = wrap(Zap);
export const ZapOffIcon             = wrap(ZapOff);
export const MicLucideIcon          = wrap(Mic);
export const FolderOpenLucideIcon   = wrap(FolderOpen);
export const TerminalLucideIcon     = wrap(Terminal);
export const SearchLucideIcon       = wrap(Search);
export const GlobeLucideIcon        = wrap(Globe);
export const BotLucideIcon          = wrap(Bot);
export const SettingsLucideIcon     = wrap(Settings);
