export type Track = {
	id: string;
	url: string;
	title: string;
	artwork: string;
	artist: string;
};

export const playlist: Track[] = [
	{
		id: 'remote-track-1',
		url: 'https://rnap.dev/audio-soundhelix-song-1-tschurger.mp3',
		title: 'Soundhelix Song 1',
		artwork: 'https://rnap.dev/artwork-usgs-bAji8qv_LlY-unsplash.jpg',
		artist: 'T. Schurger',
	},
	{
		id: 'remote-track-2',
		url: 'https://rnap.dev/audio-soundhelix-song-2-tschurger.mp3',
		title: 'Soundhelix Song 2',
		artwork: 'https://rnap.dev/artwork-usgs-8tfu4320oxI-unsplash.jpg',
		artist: 'T. Schurger',
	},
	// {
	// 	id: 'error-track-1',
	// 	url: 'https://error',
	// 	title: 'This track should error',
	// 	artwork: 'https://error',
	// 	artist: 'For test purposes',
	// },
];
