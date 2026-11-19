// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
	site: 'https://hometv.nziranziza.workers.dev',
	integrations: [
		starlight({
			title: 'HomeTV',
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/Nziranziza/home-tv' }],
			editLink: { baseUrl: 'https://github.com/Nziranziza/home-tv/edit/main/docs/' },
			sidebar: [
				{ label: 'Overview', link: '/' },
				{
					label: 'User guide',
					items: [
						'guide/install',
						'guide/setup-and-addons',
						'guide/watch-now',
						'guide/titles-episodes-cast',
						'guide/search',
						'guide/playback',
						'guide/trakt-and-library',
						'guide/top-shelf-settings-faq',
					],
				},
				{
					label: 'Developers',
					items: [
						'developers/build-from-source',
						'developers/architecture',
						'developers/playback-architecture',
						'developers/contributing',
						'developers/licenses',
					],
				},
			],
		}),
	],
});
